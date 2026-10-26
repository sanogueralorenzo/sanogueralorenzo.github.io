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

    /// Where the pointer clicked the link `navigationAction` follows, for a
    /// link the person activated, which a Peek grows from.
    func linkSourcePresentation(
        for navigationAction: WKNavigationAction, in webView: WKWebView
    ) -> BrowserPeekSourcePresentation? {
        navigationAction.navigationType == .linkActivated
            ? peekSourcePresentation(for: navigationAction.request.url, in: webView) : nil
    }

    /// Opens a modified click's link in a new tab of the page's Space.
    func routeModifiedLink(_ request: URLRequest, selecting: Bool) {
        openModifiedLink(request, spaceID, selecting)
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
        decideResponsePolicy(for: navigationResponse, in: webView, decisionHandler: decisionHandler)
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
        answerChallenge(challenge, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
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
            // The page keeps a clear under-page colour until its first load
            // finishes, so it follows the count once the count has moved.
            self.updateUnderPageBackground()
            self.webKitAdapter?.reporter?.finished(finishedURL, title: title)
        }
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
