import Foundation
import WebKit

/// The page's navigation gates that read WebKit's own navigation objects.
extension BrowserPlatformPage {
    /// The WebKit port behind this page, or nil when another engine hosts it.
    var webKitEngine: BrowserWebKitPageEngine? { (pageEngine as any BrowserPageEngine) as? BrowserWebKitPageEngine }

    /// Tells the core WebKit ended the page's web content process. The core
    /// decides whether WebKit reloads it now, once a window shows it, or
    /// whether the page shows the failure.
    func reportWebContentProcessStopped() {
        corePage.report(
            PageCrashed(
                pageID: corePage.id, domain: WKError.errorDomain,
                code: Int64(WKError.Code.webContentProcessTerminated.rawValue)))
    }

    /// True when Crest, not web content, asked for this navigation. Two signals
    /// answer that: the exact URL Crest last passed to `load(_:)`, which web
    /// content never reaches, and a source frame that is not a web document —
    /// WebKit reports an empty origin for a load the app started against a web
    /// view with no page yet, and a `file:` origin for a local document's own
    /// links. Only such a navigation may reach a `file:` URL.
    func isAppInitiated(_ navigationAction: WKNavigationAction) -> Bool {
        if let appInitiatedURL, navigationAction.request.url == appInitiatedURL {
            return true
        }
        if let sourceOriginProvider = navigationAction as? any BrowserNavigationActionSourceOriginProviding {
            guard let origin = sourceOriginProvider.browserSourceOrigin else {
                return false
            }
            if origin.scheme.isEmpty, origin.host.isEmpty {
                return true
            }
            return origin.scheme == "file"
        }
        let origin = navigationAction.sourceFrame.securityOrigin
        let scheme = origin.protocol.lowercased()
        if scheme.isEmpty, origin.host.isEmpty {
            return true
        }
        return scheme == "file"
    }

    /// Lets the core judge the link `navigationAction` follows, once WebKit may
    /// load it, and answers WebKit. Each platform says where the person
    /// activated the link and opens a modified click's tab.
    func decideLinkPolicy(
        for navigationAction: WKNavigationAction,
        in webView: WKWebView,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let sourcePresentation = linkSourcePresentation(for: navigationAction, in: webView)
        // The core decides what the link does, as it does for Chromium's.
        let webKitPage = webKitEnginePage
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

    /// Answers WebKit for a navigation's response: a media file the page opened
    /// directly plays in a document of its own, and anything else loads when
    /// WebKit can show it.
    func decideResponsePolicy(
        for navigationResponse: WKNavigationResponse,
        in webView: WKWebView,
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

    /// Lets the page's host retire the page when its first navigation became
    /// a download, leaving it with nothing to show.
    func discardDownloadOnlySurfaceIfNeeded() {
        guard committedNavigationCount == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, committedNavigationCount == 0 else { return }
            host?.discardDownloadOnlyPage(self)
        }
    }

    func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        // WebKit can deliver a callback late, after its navigation finished or
        // was replaced. An identified navigation is only current while it is
        // still the active one, so a stale failure cannot paint an error over a
        // page that already loaded. Callbacks that identify no navigation stay
        // accepted because WebKit reports unattributed loads that way.
        guard let navigation else { return true }
        return activeNavigation === navigation
    }
}
