import Foundation
import WebKit

@MainActor
final class BrowserGeolocationScriptMessageProxy: NSObject, WKScriptMessageHandler {
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
