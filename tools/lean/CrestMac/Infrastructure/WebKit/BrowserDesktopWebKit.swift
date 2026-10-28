import AppKit
import WebKit

/// What only the Mac's WebKit pages need, which WebKit's binding applies as it
/// builds a page: sites asked for their desktop presentation, the inspector
/// and Picture in Picture turned on, and the desktop web view.
@MainActor
enum BrowserDesktopWebKit {
    // MARK: - Static Variables

    static let preferredContentMode = WKWebpagePreferences.ContentMode.desktop

    // MARK: - Actions - Pages

    /// A new page's configuration keeps the settings both platforms share.
    static func decorate(_ configuration: WKWebViewConfiguration) {}

    /// The desktop web view over `configuration`, one the binding assembled or
    /// one WebKit made for a popup.
    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let interval = BrowserPage.lifecycleSignposter.beginInterval("Initialize WKWebView")
        defer { BrowserPage.lifecycleSignposter.endInterval("Initialize WKWebView", interval) }
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        BrowserDesktopPictureInPictureAccess.enable(in: configuration.preferences)
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        let webView = BrowserDesktopWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        return webView
    }
}
