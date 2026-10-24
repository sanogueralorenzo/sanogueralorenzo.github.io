import WebKit

@testable import Crest

extension BrowserPage {
    /// The web view behind a page the WebKit composition built. The suites
    /// drive WebKit pages directly; a page from another engine is a test error.
    var webView: WKWebView {
        guard let webView = webKitView else { preconditionFailure("The page is not hosted by WebKit.") }
        return webView
    }
}
