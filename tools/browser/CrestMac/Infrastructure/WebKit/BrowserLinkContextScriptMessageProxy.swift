import Foundation
import WebKit

/// Forwards the link-context bridge's messages without becoming a retain cycle.
///
/// `WKUserContentController` owns every handler it is given, and the page owns
/// the controller. The page hands over this proxy and captures itself weakly in
/// `receive`, exactly as the credential bridge does.
@MainActor
final class BrowserLinkContextScriptMessageProxy: NSObject, WKScriptMessageHandler {
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
