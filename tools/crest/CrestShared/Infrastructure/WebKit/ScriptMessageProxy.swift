import Foundation
import WebKit

/// Forwards a content bridge's messages to `receive` without becoming a retain
/// cycle.
///
/// `WKUserContentController` owns every handler it is given, and the page owns
/// the controller. A page hands over this proxy and captures itself weakly in
/// `receive`.
@MainActor
final class BrowserScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private let receive: @MainActor (WKScriptMessage) -> Void

    init(receive: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receive(message)
    }
}
