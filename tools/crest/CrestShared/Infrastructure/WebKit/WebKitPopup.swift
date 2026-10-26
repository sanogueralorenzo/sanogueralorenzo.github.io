import WebKit

/// A popup WebKit makes for a page's document: the configuration WebKit
/// derived from its opener's, which the popup's page must use exactly as
/// given, since it carries the opener's website data store and shares its
/// user content controller, and whether the page asked for a window of its
/// own rather than a tab.
struct WebKitPopup {
    // MARK: - Variables

    let configuration: WKWebViewConfiguration
    /// Whether the page asked for a popup window, with window features, as a
    /// sign-in window does, rather than a new tab.
    let wantsWindow: Bool

    // MARK: - Initializers

    init(configuration: WKWebViewConfiguration, wantsWindow: Bool = false) {
        self.configuration = configuration
        self.wantsWindow = wantsWindow
    }
}
