import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

extension MobileBrowserPage: WKNavigationDelegate {
    private func downloadFeedbackSource(
        for destinationURL: URL?,
        in webView: WKWebView
    ) -> BrowserDownloadFeedbackSource? {
        guard
            let capture = downloadSourceStore.consume(
                destinationURL: destinationURL
            ),
            let window = webView.window,
            webView.bounds.width > 0,
            webView.bounds.height > 0
        else { return nil }
        let pointInWebView = CGPoint(
            x: capture.normalizedTouchPoint.x * webView.bounds.width,
            y: capture.normalizedTouchPoint.y * webView.bounds.height
        )
        let pointInWindow = webView.convert(pointInWebView, to: window)
        guard pointInWindow.x.isFinite, pointInWindow.y.isFinite else {
            return nil
        }
        return BrowserDownloadFeedbackSource(
            pointInGlobal: pointInWindow,
            windowIdentifier: ObjectIdentifier(window)
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        translation.reset()
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.cancelAll()
        activeNavigation = navigation
        // Reloads and history traversal do not necessarily pass through the
        // app-level load path. Retire the old document's session as soon as
        // WebKit starts any replacement navigation.
        mediaSessionCoordinator?.prepareForNavigation()
        isAwaitingPopupNavigation = false
        beginBlockedPopupNavigation()
        beginGeolocationNavigation()
        // WebKit accepted the navigation Crest asked for, so the authorization
        // that came with it is spent.
        consumeAppInitiatedURL()
        pendingServerTrustIdentity = nil
        linkActivationSourceStore.removeAll()
        credentialState.didStartNavigation()
        readerModeSession.invalidate()
        faviconSession.invalidate()
        reporter.started(webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        if let url = webView.url { reporter.committed(url) }
        mediaSessionCoordinator?.didCommitNavigation()
        committedNavigationCount &+= 1
        // A new document drops the supplements that described the old one; a
        // return to history keeps the entries the person may go forward to.
        navigationHistory.documentDidCommit(in: webView.backForwardList)
        refreshNavigationState()
        webKitPage.resetAutomaticDownloads()
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation),
            let redirectedURL = webView.url
        else { return }
        reporter.redirected(to: redirectedURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        completeNavigation()
        mediaSessionCoordinator?.didFinishNavigation()
        Task { [weak self] in
            await self?.refreshReaderModeAvailability()
        }
        Task {
            await httpAuthenticationSession.authenticationSucceeded()
        }
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
        let gesture = navigationAction.linkGesture
        let sourcePresentation =
            gesture.userActivated && gesture.topLevel
            ? linkActivationSourceStore.consume(
                destinationURL: navigationAction.request.url
            )
            : nil
        // The core decides what the link does, as it does for Chromium's.
        let decision = webKitPage.linkActivation(to: navigationAction.request.url, gesture: gesture)
        // A modified click keeps its initiator's referrer through a staged
        // request; a saved-site Peek starts afresh, as it does on Chromium.
        let engineNavigation = decision.stagesLink ? webKitPage.stageLink(navigationAction.request) : nil
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
            routeModifiedLink(navigationAction.request, selecting: decision.selectsTab)
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
        startDownload(download, feedbackSource: feedbackSource)
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
        startDownload(download, feedbackSource: feedbackSource)
        discardDownloadOnlySurfaceIfNeeded()
    }

    /// Hands a download the page's web view started to WebKit's binding, which
    /// runs it as the engine's own, and shows it leaving from where the
    /// person started it. Only Crest's trusted activation bridge counts it as
    /// the person's own.
    private func startDownload(_ download: WKDownload, feedbackSource: BrowserDownloadFeedbackSource?) {
        if let feedbackSource {
            downloadCenter.presentFeedback(
                BrowserDownloadFeedbackEvent(
                    id: UUID(), profileID: profileID, spaceID: spaceID,
                    filename: download.originalRequest?.url?.lastPathComponent.nilIfEmpty ?? "download",
                    source: feedbackSource))
        }
        webKitPage.startDownload(
            download,
            isUserInitiated: feedbackSource != nil)
    }

    func discardDownloadOnlySurfaceIfNeeded() {
        guard committedNavigationCount == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, committedNavigationCount == 0 else { return }
            host?.discardDownloadOnlyPage(self)
        }
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
        answerSignIn(challenge, from: webKitPage, completionHandler: completionHandler)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        faviconSession.invalidate()
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.webContentProcessDidTerminate()
        httpAuthenticationSession.authenticationFailed()
        recordWebContentTermination()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
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
        httpAuthenticationSession.authenticationFailed()
        recordNavigationFailure(
            error,
            replacedDocument: false,
            navigation: navigation
        )
    }
}
