import Foundation
import WebKit

/// What a new-window request's own URL scheme settles before any pop-up
/// permission is consulted. Each route resolves the request itself.
///
/// `window.open("mailto:…")` is the case this exists for: the destination belongs
/// to another application, so it must never become a tab. Opening one and then
/// handing the URL off leaves an empty tab behind that the user has to notice and
/// close.
struct BrowserPopupSchemeRouting: Equatable, Sendable {
    // MARK: - Static Variables

    /// WebKit can host the destination, so the pop-up policy decides.
    static let popupPolicy = BrowserPopupSchemeRouting(name: "popupPolicy", destination: nil) {
        _, navigationAction, _, offer in
        // WebKit has already enforced its user-activation / automatic-window
        // preference before this delegate runs. The popup keeps its opener only
        // when WebKit gets the web view it built from `configuration` back
        // synchronously, which the core's adoption provides.
        offer(navigationAction.request.url)
    }
    /// Nothing may load it and nothing may open it.
    static let blocked = BrowserPopupSchemeRouting(name: "blocked", destination: nil) { _, _, _, _ in nil }

    // MARK: - Types

    /// Resolves one new-window request on the coordinator, given the request's
    /// destination and how to offer the popup WebKit made.
    typealias Resolve =
        @MainActor @Sendable (
            BrowserPopupCoordinator, WKNavigationAction, _ currentURL: URL?, _ offer: (URL?) -> WKWebView?
        ) -> WKWebView?

    // MARK: - Variables

    let name: String
    /// The destination a hand-off gives another application.
    let destination: URL?
    private let resolve: Resolve

    // MARK: - Initializers

    private init(name: String, destination: URL?, resolve: @escaping Resolve) {
        self.name = name
        self.destination = destination
        self.resolve = resolve
    }

    // MARK: - Actions - Routing

    /// Another application owns the destination: hand it off, open no tab.
    static func handOffToSystem(_ url: URL) -> BrowserPopupSchemeRouting {
        BrowserPopupSchemeRouting(name: "handOffToSystem", destination: url) {
            coordinator, navigationAction, currentURL, _ in
            coordinator.handOff(url, for: navigationAction, currentURL: currentURL)
            return nil
        }
    }

    /// A popup destination is never app-initiated, so `file:` is refused here for
    /// the same reason it is refused for an ordinary navigation.
    static func classify(destinationURL: URL?) -> Self {
        switch SchemeHandling.disposition(for: destinationURL).kind {
        case .engine:
            return .popupPolicy
        case .blocked:
            return .blocked
        case .handOff:
            guard let destinationURL else { return .blocked }
            return .handOffToSystem(destinationURL)
        }
    }

    /// Resolves the new-window request `navigationAction` on `coordinator`:
    /// the popup WebKit made, from `offer`, or none.
    @MainActor func resolve(
        _ navigationAction: WKNavigationAction, currentURL: URL?, on coordinator: BrowserPopupCoordinator,
        offer: (URL?) -> WKWebView?
    ) -> WKWebView? {
        resolve(coordinator, navigationAction, currentURL, offer)
    }

    // MARK: - Equatable

    static func == (lhs: BrowserPopupSchemeRouting, rhs: BrowserPopupSchemeRouting) -> Bool {
        lhs.name == rhs.name && lhs.destination == rhs.destination
    }
}
