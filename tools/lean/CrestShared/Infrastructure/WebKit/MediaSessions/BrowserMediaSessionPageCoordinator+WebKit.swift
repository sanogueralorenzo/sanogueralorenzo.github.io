import Foundation
import WebKit

extension BrowserMediaSessionPageCoordinator {
    /// Binds a WebKit page, whose Media Session bridge Crest runs in the page.
    convenience init(
        webView: WKWebView,
        endpoint: any BrowserMediaSessionCommandEndpoint,
        store: BrowserMediaSessionStore,
        owner: @escaping @MainActor () -> BrowserTabRuntimeAssignment?,
        fallbackTitle: @escaping @MainActor () -> String?
    ) {
        self.init(
            owning: BrowserWebKitMediaSessionTransport(webView: webView), endpoint: endpoint, store: store,
            owner: owner, fallbackTitle: fallbackTitle)
    }

    /// A bridge message, accepted only from this coordinator's own web view.
    func receive(_ message: WKScriptMessage) {
        guard let transport = ownedTransport as? BrowserWebKitMediaSessionTransport,
            message.webView === transport.webView
        else { return }
        receive(message.body, isMainFrame: message.frameInfo.isMainFrame)
    }
}
