import Foundation
import WebKit

extension BrowserTranslationDocument {
    static let webKitWorld = WKContentWorld.world(name: "Browser.PageTranslation")

    init(webView: WKWebView) {
        self.init { [weak webView] body, arguments in
            try await webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.webKitWorld)
        }
    }
}
