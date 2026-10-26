import Foundation
import WebKit

@MainActor
final class BrowserWebKitFaviconDocument: BrowserFaviconDocument {
    private let webView: WKWebView
    private let profileID: UUID

    init(webView: WKWebView, profileID: UUID) {
        self.webView = webView
        self.profileID = profileID
    }

    var url: URL? { webView.url }

    func capture() async -> Data? {
        await BrowserFaviconCapture.capture(from: webView)
    }

    func fallback(for url: URL) async -> Data? {
        await BrowserFaviconFallbackLoader.shared.data(for: url, profileID: profileID)
    }
}
