import Foundation
import WebKit

// MARK: - Actions - Script messages

extension BrowserPageOwner {
    // A popup shares its opener's `WKUserContentController`, so its bridges
    // post to the opener's handlers; each message goes to the page whose web
    // view sent it.

    func routeGeolocationMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveGeolocationMessage(message)
    }

    func routeBlockedPopupMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveBlockedPopupMessage(message)
    }

    func routeMediaSessionMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveMediaSessionMessage(message)
    }

    /// The resident page whose web view posted `message`.
    func residentPage(sending message: WKScriptMessage) -> BrowserPlatformPage? {
        guard let sourceWebView = message.webView else { return nil }
        return host.residentPages.first { $0.webKitView === sourceWebView }
    }
}
