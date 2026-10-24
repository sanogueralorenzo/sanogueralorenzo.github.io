import WebKit

/// Popups share their opener's user-content controller. Install once on that
/// controller and route each message to the exact web view that authored it.
@MainActor
final class BrowserPictureInPictureContentBridge: NSObject, WKScriptMessageHandler {
    static let shared = BrowserPictureInPictureContentBridge()
    static let contentWorld = WKContentWorld.world(name: "CrestPictureInPicture")
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()
    private let pages = NSMapTable<WKWebView, BrowserPictureInPicturePageController>.weakToWeakObjects()

    func install(in controller: WKUserContentController) {
        guard !installedControllers.contains(controller) else { return }
        installedControllers.add(controller)
        controller.add(self, contentWorld: Self.contentWorld, name: "crestPictureInPicture")
        controller.addUserScript(
            WKUserScript(
                source: BrowserPictureInPictureScript.source, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: Self.contentWorld
            ))
    }

    func register(_ page: BrowserPictureInPicturePageController, webView: WKWebView) {
        pages.setObject(page, forKey: webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView else { return }
        pages.object(forKey: webView)?.receive(message)
    }
}
