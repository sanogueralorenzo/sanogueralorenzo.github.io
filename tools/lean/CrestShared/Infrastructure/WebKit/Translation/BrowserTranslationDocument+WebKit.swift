import Foundation
import WebKit

/// WebKit evaluates the translation bridge in a content world of its own, in
/// the web view's main frame.
extension BrowserTranslationDocument {
    static let webKitWorld = WKContentWorld.world(name: "Crest.PageTranslation")

    init(webView: WKWebView) {
        self.init { [weak webView] body, arguments in
            try await webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.webKitWorld)
        }
    }
}
