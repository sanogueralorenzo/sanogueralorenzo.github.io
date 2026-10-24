import Foundation
import WebKit

@MainActor
final class BrowserUserActivityScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private let receive: @MainActor () -> Void

    init(receive: @escaping @MainActor () -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == BrowserUserActivityBridge.messageHandlerName else { return }
        receive()
    }
}
