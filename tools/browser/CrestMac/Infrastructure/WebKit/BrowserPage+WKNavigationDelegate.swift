import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit

extension BrowserPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        translation.reset()
        linkHover?.beginNavigation()
        linkDrag?.beginNavigation()
        focusRestoration.invalidate()
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.cancelAll()
        activeNavigation = navigation
        // Reloads and history traversal do not necessarily pass through the
        // app-level load path. Retire the old document's session as soon as
        // WebKit starts any replacement navigation.
        mediaSessionCoordinator?.prepareForNavigation()
        pictureInPicture?.invalidate()
        isAwaitingPopupNavigation = false
        beginBlockedPopupNavigation()
        beginGeolocationNavigation()
        beginHostedWebNotificationNavigation()
        // WebKit accepted the navigation Crest asked for, so the authorization
        // that came with it is spent.
        consumeAppInitiatedURL()
        pendingServerTrustIdentity = nil
        credentialState.didStartNavigation()
        readerModeSession?.invalidate()
        faviconSession?.invalidate()
        webKitAdapter?.reporter?.started(webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        if let url = webView.url { webKitAdapter?.reporter?.committed(url) }
        linkHover?.didCommitNavigation()
        linkDrag?.didFinishNavigation()
        mediaSessionCoordinator?.didCommitNavigation()
        pictureInPicture?.navigationDidCommit()
        committedNavigationCount += 1
        // A new document drops the supplements that described the old one; a
        // return to history keeps the entries the person may go forward to.
        navigationHistory.documentDidCommit(in: webView.backForwardList)
        refreshNavigationState()
        webKitAdapter?.webKitPage.resetAutomaticDownloads()
        Task { [weak self] in
            guard let self, let passkeyAccess = self.passkeyAccess,
                self.webKitView?.url?.scheme == "https",
                self.webKitView?.window?.isKeyWindow == true, NSApp.isActive
            else { return }
            await passkeyAccess.prepareForBrowsing()
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation),
            let redirectedURL = webView.url
        else { return }
        webKitAdapter?.reporter?.redirected(to: redirectedURL)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        navigationDecider.decision(
            for: navigationAction,
            isAppInitiated: isAppInitiated(navigationAction)
        ).apply(to: self, for: navigationAction, in: webView, decisionHandler: decisionHandler)
    }

    /// Lets the core judge the link `navigationAction` follows, once WebKit may
    /// load it, and answers WebKit.
    func decideLinkPolicy(
        for navigationAction: WKNavigationAction,
        in webView: WKWebView,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let sourcePresentation =
            navigationAction.navigationType == .linkActivated
            ? peekSourcePresentation(
                for: navigationAction.request.url,
                in: webView
            )
            : nil
        // The core decides what the link does, as it does for Chromium's.
        let webKitPage = webKitAdapter?.webKitPage
        let decision =
            webKitPage?.linkActivation(to: navigationAction.request.url, gesture: navigationAction.linkGesture)
            ?? .navigate
        // A modified click keeps its initiator's referrer through a staged
        // request; a saved-site Peek starts afresh, as it does on Chromium.
        let engineNavigation = decision.stagesLink ? webKitPage?.stageLink(navigationAction.request) : nil
        if let request = decision.peekRequest(
            destinationURL: navigationAction.request.url,
            context: navigationContext, sourcePresentation: sourcePresentation,
            engineNavigation: engineNavigation)
        {
            openPeek(request)
            decisionHandler(.cancel)
            return
        }
        if let engineNavigation { corePage.discardStagedLink(engineNavigation) }
        if decision.opensTab {
            openModifiedLink(navigationAction.request, spaceID, decision.selectsTab)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            if navigationAction.navigationType == .linkActivated {
                navigationHistory.recordLink(to: navigationAction.request.url, in: webView.backForwardList)
            }
            prepareForNavigation(to: navigationAction.request.url)
        }
        decisionHandler(.allow)
    }

    private func peekSourcePresentation(
        for destinationURL: URL?,
        in webView: WKWebView
    ) -> BrowserPeekSourcePresentation? {
        guard let window = webView.window, let content = window.contentView else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let pointInWebView = webView.convert(pointInWindow, from: nil)
        guard webView.bounds.contains(pointInWebView) else { return nil }

        return BrowserPeekSourcePresentation(
            touchPoint: content.convert(pointInWindow, from: nil),
            in: content.bounds.size,
            hasTopLeadingOrigin: content.isFlipped,
            label: destinationURL?.host ?? "Link"
        )
    }

    private func downloadFeedbackSource(
        for destinationURL: URL?,
        in webView: WKWebView
    ) -> BrowserDownloadFeedbackSource? {
        guard
            let capture = downloadSourceStore.consume(
                destinationURL: destinationURL
            ),
            let window = webView.window,
            let contentView = window.contentView,
            webView.bounds.width > 0,
            webView.bounds.height > 0
        else { return nil }

        var pointInWebView = CGPoint(
            x: capture.normalizedTouchPoint.x * webView.bounds.width,
            y: capture.normalizedTouchPoint.y * webView.bounds.height
        )
        if !webView.isFlipped {
            pointInWebView.y = webView.bounds.height - pointInWebView.y
        }
        let pointInWindow = webView.convert(pointInWebView, to: nil)
        let pointInContent = contentView.convert(pointInWindow, from: nil)
        let pointFromTopLeading = CGPoint(
            x: pointInContent.x,
            y: contentView.isFlipped
                ? pointInContent.y
                : contentView.bounds.height - pointInContent.y
        )
        guard pointFromTopLeading.x.isFinite,
            pointFromTopLeading.y.isFinite
        else { return nil }
        return BrowserDownloadFeedbackSource(
            pointInGlobal: pointFromTopLeading,
            windowIdentifier: ObjectIdentifier(window)
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if let mediaNavigation = BrowserDirectMediaNavigation.classify(
            canShowMIMEType: navigationResponse.canShowMIMEType,
            isForMainFrame: navigationResponse.isForMainFrame,
            response: navigationResponse.response
        ) {
            decisionHandler(.cancel)
            Task { @MainActor [weak webView] in
                webView?.loadSimulatedRequest(
                    mediaNavigation.request,
                    responseHTML: mediaNavigation.responseHTML
                )
            }
            return
        }
        decisionHandler(
            BrowserNavigationDecider.decidePolicy(
                canShowMIMEType: navigationResponse.canShowMIMEType,
                response: navigationResponse.response
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        let feedbackSource = downloadFeedbackSource(
            for: navigationAction.request.url,
            in: webView
        )
        startDownload(
            download, in: webView,
            // Only Crest's trusted activation bridge may strengthen WebKit's own
            // initiation signal. A synthetic `.linkActivated` navigation is not proof
            // of a user gesture and must remain subject to automatic-download policy.
            isUserInitiated: feedbackSource != nil,
            feedbackSource: feedbackSource)
        discardDownloadOnlySurfaceIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let feedbackSource = downloadFeedbackSource(
            for: download.originalRequest?.url
                ?? navigationResponse.response.url,
            in: webView
        )
        startDownload(
            download, in: webView,
            isUserInitiated: feedbackSource != nil,
            feedbackSource: feedbackSource)
        discardDownloadOnlySurfaceIfNeeded()
    }

    /// Hands a download the page's web view started to WebKit's binding, which
    /// runs it as the engine's own. Once the core says it began, the page
    /// shows it leaving, from the link the person clicked when the pointer
    /// has left the page.
    func startDownload(
        _ download: WKDownload, in webView: WKWebView, isUserInitiated: Bool,
        feedbackSource: BrowserDownloadFeedbackSource? = nil
    ) {
        guard let webKitPage = webKitAdapter?.webKitPage else {
            download.cancel { _ in }
            return
        }
        startedDownloadSource = feedbackSource
        webKitPage.startDownload(download, isUserInitiated: isUserInitiated)
    }

    func discardDownloadOnlySurfaceIfNeeded() {
        guard committedNavigationCount == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, committedNavigationCount == 0 else { return }
            host?.discardDownloadOnlyPage(self)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        faviconSession?.invalidate()
        translation.reset()
        readerModeSession?.invalidate()
        linkHover?.beginNavigation()
        linkDrag?.beginNavigation()
        focusRestoration.invalidate()
        mediaSessionCoordinator?.webContentProcessDidTerminate()
        pictureInPicture?.invalidate()
        credentialState.webContentProcessDidTerminate()
        httpAuthenticationSession.authenticationFailed()
        reportWebContentProcessStopped()
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:
            @escaping @MainActor @Sendable (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
    ) {
        if let identity = BrowserServerTrustIdentity.challengeIdentity(
            for: challenge
        ) {
            if serverTrustOverrides.isApproved(identity, for: profileID),
                let trust = challenge.protectionSpace.serverTrust
            {
                pendingServerTrustIdentity = nil
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                pendingServerTrustIdentity = identity
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }
        answerSignIn(challenge, from: webKitAdapter?.webKitPage, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        #if CREST_PERFORMANCE_HARNESS
            BrowserPerformanceProcessReporter.report(webView: webView)
        #endif
        guard isCurrentNavigation(navigation) else { return }
        activeNavigation = nil
        let committedNavigation = committedNavigationCount
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            let documentTitle = try? await webView.evaluateJavaScript("document.title") as? String
            // A move within the document while its title was read, such as a
            // script router's first `replaceState`, belongs to this load,
            // which finishes where the document is now.
            guard self.activeNavigation == nil,
                self.committedNavigationCount == committedNavigation,
                let finishedURL = webView.url
            else { return }
            let title = documentTitle?.isEmpty == false ? documentTitle : webView.title
            self.completedNavigationCount += 1
            self.webKitAdapter?.reporter?.finished(finishedURL, title: title)
        }
        updateUnderPageBackground()
        mediaSessionCoordinator?.didFinishNavigation()
        refreshFavicon()
        Task { [weak self] in
            await self?.refreshReaderModeAvailability()
        }
        Task {
            await httpAuthenticationSession.authenticationSucceeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        if isCurrentNavigation(navigation) {
            linkHover?.didFailNavigation()
            linkDrag?.didFinishNavigation()
        }
        httpAuthenticationSession.authenticationFailed()
        recordNavigationFailure(
            error,
            replacedDocument: true,
            navigation: navigation
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        if isCurrentNavigation(navigation) {
            linkHover?.didFailNavigation()
            linkDrag?.didFinishNavigation()
        }
        httpAuthenticationSession.authenticationFailed()
        recordNavigationFailure(
            error,
            replacedDocument: false,
            navigation: navigation
        )
    }
}
