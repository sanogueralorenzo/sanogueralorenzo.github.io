import Foundation
import WebKit

/// What a WebKit page does with one navigation before the core judges its link.
/// Each decision answers WebKit itself: a plain policy, a hand-off that cancels
/// and passes the URL to the platform's opener, or the page's own link handling.
struct BrowserNavigationDecision: Equatable, Sendable {
    // MARK: - Static Variables

    /// WebKit may load it; the page's link handling decides the rest.
    static let allow = BrowserNavigationDecision(name: "allow", destination: nil) {
        page, navigationAction, webView, decisionHandler in
        page.decideLinkPolicy(for: navigationAction, in: webView, decisionHandler: decisionHandler)
    }
    /// WebKit downloads it.
    static let download = BrowserNavigationDecision(name: "download", destination: nil) { _, _, _, decisionHandler in
        decisionHandler(.download)
    }
    /// Nothing may load this URL and nothing may open it.
    static let blockScheme = BrowserNavigationDecision(name: "blockScheme", destination: nil) {
        _, _, _, decisionHandler in
        decisionHandler(.cancel)
    }

    // MARK: - Types

    /// Answers WebKit for one navigation on the page that received it.
    typealias Apply =
        @MainActor @Sendable (
            BrowserPlatformPage, WKNavigationAction, WKWebView,
            _ decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) -> Void

    // MARK: - Variables

    let name: String
    /// The destination a new tab or a hand-off names.
    let destination: URL?
    private let apply: Apply

    // MARK: - Initializers

    private init(name: String, destination: URL?, apply: @escaping Apply) {
        self.name = name
        self.destination = destination
        self.apply = apply
    }

    // MARK: - Actions - Decisions

    /// A navigation with no target frame wants a new tab.
    static func openInNewTab(_ url: URL) -> BrowserNavigationDecision {
        BrowserNavigationDecision(name: "openInNewTab", destination: url) {
            page, navigationAction, webView, decisionHandler in
            // Allow WebKit to continue to WKUIDelegate.createWebViewWith,
            // where Crest can apply the owning Space's pop-up policy exactly once.
            page.decideLinkPolicy(for: navigationAction, in: webView, decisionHandler: decisionHandler)
        }
    }

    /// Another application owns this URL. The page cancels and hands it over.
    static func handOffToSystem(_ url: URL) -> BrowserNavigationDecision {
        BrowserNavigationDecision(name: "handOffToSystem", destination: url) {
            page, navigationAction, _, decisionHandler in
            // Cancelling before `prepareForNavigation` is what keeps the
            // hand-off out of the error page: nothing is pending to fail, and
            // WebKit's own cancellation error is an expected interruption.
            page.externalSchemeCoordinator.handOff(
                destinationURL: url,
                trigger: BrowserPopupTrigger.classify(navigationAction.navigationType),
                origin: page.externalSchemeCoordinator.sourceOrigin(
                    for: navigationAction,
                    currentURL: page.live.displayURL
                )
            )
            decisionHandler(.cancel)
        }
    }

    static func classify(
        url: URL?,
        hasTargetFrame: Bool,
        shouldPerformDownload: Bool,
        isAppInitiated: Bool = false
    ) -> BrowserNavigationDecision {
        // The scheme is settled first: a `mailto:` link with `target="_blank"`
        // belongs to the mail client, not to a new Crest tab, and a scheme Crest
        // refuses must not become a download either.
        switch SchemeHandling.disposition(
            for: url,
            isAppInitiated: isAppInitiated
        ).kind {
        case .engine:
            break
        case .blocked:
            return .blockScheme
        case .handOff:
            if let url {
                return .handOffToSystem(url)
            }
        }
        if shouldPerformDownload {
            return .download
        }
        if !hasTargetFrame, let url {
            return .openInNewTab(url)
        }
        return .allow
    }

    /// Answers WebKit for `navigationAction` on `page`.
    @MainActor func apply(
        to page: BrowserPlatformPage,
        for navigationAction: WKNavigationAction,
        in webView: WKWebView,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        apply(page, navigationAction, webView, decisionHandler)
    }

    // MARK: - Equatable

    static func == (lhs: BrowserNavigationDecision, rhs: BrowserNavigationDecision) -> Bool {
        lhs.name == rhs.name && lhs.destination == rhs.destination
    }
}
