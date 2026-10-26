import Foundation
import WebKit

@MainActor
final class BrowserWebKitFaviconDocument: NSObject, BrowserFaviconDocument, WKScriptMessageHandler {
    // MARK: - Static Variables

    private static let messageName = "crestFaviconChanged"
    private static let observerSource = #"""
        if (!globalThis.__crestFaviconObserver && document.head) {
          const signature = () => [...document.head.querySelectorAll('link[rel][href]')]
            .filter(link => link.rel.split(/\s+/).includes('icon'))
            .map(link => [link.href, link.media, link.type, link.sizes.value].join('|')).join('\n');
          let previous = signature(), timer;
          globalThis.__crestFaviconObserver = new MutationObserver(() => {
            const current = signature();
            if (current === previous) return;
            previous = current;
            clearTimeout(timer);
            timer = setTimeout(() => webkit.messageHandlers.crestFaviconChanged.postMessage(null), 100);
          });
          globalThis.__crestFaviconObserver.observe(document.head, {
            subtree: true, childList: true, attributes: true,
            attributeFilter: ['href', 'rel', 'media', 'type', 'sizes']
          });
        }
        """#

    // MARK: - Variables

    private weak var webView: WKWebView?
    private let profileID: UUID
    private var iconChanged: (@MainActor () -> Void)?
    var url: URL? { webView?.url }

    // MARK: - Initializers

    init(webView: WKWebView, profileID: UUID) {
        self.webView = webView
        self.profileID = profileID
        super.init()
    }

    // MARK: - Actions - Observation

    func observeIconChanges(_ changed: @escaping @MainActor () -> Void) {
        iconChanged = changed
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.messageName, contentWorld: .defaultClient)
        controller.add(self, contentWorld: .defaultClient, name: Self.messageName)
        controller.addUserScript(
            WKUserScript(
                source: Self.observerSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        if webView.url != nil {
            Task { @MainActor [weak webView] in
                _ = try? await webView?.callAsyncJavaScript(
                    Self.observerSource, arguments: [:], in: nil, contentWorld: .defaultClient)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame else { return }
        iconChanged?()
    }

    // MARK: - Actions - Capture

    func capture() async -> Data? {
        guard let webView else { return nil }
        return await BrowserFaviconCapture.capture(from: webView)
    }

    func fallback(for url: URL) async -> Data? {
        await BrowserFaviconFallbackLoader.shared.data(for: url, profileID: profileID)
    }
}
