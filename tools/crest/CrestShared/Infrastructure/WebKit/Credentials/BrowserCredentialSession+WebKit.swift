import Foundation
import WebKit

/// WebKit delivers the credential bridge through its own user content
/// controller and evaluates fills in the frame and content world it named.
extension BrowserCredentialSession {
    func receive(_ scriptMessage: WKScriptMessage, in webView: WKWebView) {
        guard scriptMessage.webView === webView,
            scriptMessage.name == BrowserCredentialContentBridge.messageHandlerName
        else { return }
        let origin = scriptMessage.frameInfo.securityOrigin
        receive(
            scriptMessage.body,
            from: BrowserContentFrame(
                isMainFrame: scriptMessage.frameInfo.isMainFrame,
                securityProtocol: origin.protocol,
                host: origin.host,
                port: origin.port,
                handle: scriptMessage.frameInfo
            ),
            topLevelURL: webView.url
        )
    }

    func fill(_ credential: BrowserCredential, for requestID: UUID, in webView: WKWebView) async throws {
        try await fill(credential, for: requestID, evaluate: Self.evaluator(in: webView))
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID, in webView: WKWebView) async throws {
        try await fillGeneratedPassword(password, for: requestID, evaluate: Self.evaluator(in: webView))
    }

    static func evaluator(in webView: WKWebView) -> Evaluate {
        { [weak webView] body, arguments, frame in
            guard let webView, let frameInfo = frame.handle as? WKFrameInfo else {
                throw BrowserCredentialFillError.formChanged
            }
            return try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: frameInfo,
                contentWorld: BrowserCredentialContentBridge.contentWorld
            )
        }
    }
}
