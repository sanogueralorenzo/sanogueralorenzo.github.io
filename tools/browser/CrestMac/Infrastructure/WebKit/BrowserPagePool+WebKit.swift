import Foundation
import WebKit

/// The pool's WebKit hosting that only a Mac window does: the hosted web
/// notifications its bridges post. What every page owner does with WebKit
/// lives in `BrowserPageOwner`.
extension BrowserPagePool {
    // MARK: - Actions - Script message routing

    func routeHostedWebNotificationMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveHostedWebNotificationMessage(message)
    }
}
