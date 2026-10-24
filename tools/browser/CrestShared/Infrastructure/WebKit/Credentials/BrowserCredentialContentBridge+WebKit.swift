import Foundation
import WebKit

// MARK: - Actions - WebKit

extension BrowserCredentialContentBridge {
    static let contentWorld = WKContentWorld.world(name: "com.pauldavis.crest.credentials")

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserCredentialScriptMessageProxy {
        let proxy = BrowserCredentialScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
    }
}
