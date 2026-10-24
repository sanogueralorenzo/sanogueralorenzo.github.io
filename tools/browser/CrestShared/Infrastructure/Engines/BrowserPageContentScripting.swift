import Foundation

/// The document a content-bridge message came from. Only the adapter that
/// produced it can resolve `handle`; shared code keeps it to address an
/// evaluation back to the same document.
struct BrowserContentFrame {
    let isMainFrame: Bool
    let securityProtocol: String
    let host: String
    let port: Int
    let handle: AnyObject
}

struct BrowserContentMessage {
    let handlerName: String
    let body: Any
    let frame: BrowserContentFrame
}

/// A script one of Crest's content bridges runs in every document of a page.
/// Bridges post through `webkit.messageHandlers.<handlerName>` on both engines.
struct BrowserContentScript {
    let source: String
    let handlerName: String
    let mainFrameOnly: Bool
}

/// Content bridges on an engine that runs them itself. The bridges live in an
/// isolated world the page cannot see. WebKit pages still install their
/// bridges through their own user content controller.
@MainActor
protocol BrowserPageContentScripting: AnyObject {
    func install(_ script: BrowserContentScript, receive: @escaping @MainActor (BrowserContentMessage) -> Void) -> Bool
    /// Runs `body` as the body of an async function with `arguments` bound as
    /// constants, in the document `frame` names. Answers nil when that
    /// document is gone.
    func callAsyncJavaScript(
        _ body: String,
        arguments: [String: Any],
        in frame: BrowserContentFrame
    ) async throws -> Any?
    /// Runs `body` as `callAsyncJavaScript` does, in the page's current main
    /// document. Answers nil when the page has none.
    func callAsyncJavaScriptInMainFrame(_ body: String, arguments: [String: Any]) async throws -> Any?
}
