import Foundation

/// The page's main document as whole-page translation reads and rewrites it:
/// Crest's translation bridge, run in an isolated world the page cannot see
/// through whichever engine shows the page. The page's engine adapter supplies
/// it, with the engine's own way to evaluate that bridge.
@MainActor
struct BrowserTranslationDocument {
    // MARK: - Types

    /// Runs `body` as the body of an async function with `arguments` bound as
    /// constants, in the main document's translation world, and answers its
    /// result, or nil when the document is gone.
    typealias Evaluate = @MainActor (_ body: String, _ arguments: [String: Any]) async throws -> Any?

    struct Sample: Sendable {
        let text: String
        let declaredLanguage: String
    }

    struct Capture {
        let texts: [String]
        let isLimited: Bool
    }

    struct Update: Sendable {
        let index: Int
        let text: String
    }

    // MARK: - Variables

    private let evaluate: Evaluate

    // MARK: - Initializers

    init(evaluate: @escaping Evaluate) {
        self.evaluate = evaluate
    }

    /// The main document of a page whose engine runs Crest's content bridges
    /// itself.
    init(mainFrameOf scripting: any BrowserPageContentScripting) {
        evaluate = { [weak scripting] body, arguments in
            try await scripting?.callAsyncJavaScriptInMainFrame(body, arguments: arguments)
        }
    }

    // MARK: - Actions - Document

    func sample() async throws -> Sample {
        let value = try await perform("sample") as? [String: Any]
        return Sample(text: value?["text"] as? String ?? "", declaredLanguage: value?["language"] as? String ?? "")
    }

    func capture(token: String) async throws -> Capture {
        let value = try await perform("capture", token: token) as? [String: Any]
        return Capture(texts: value?["texts"] as? [String] ?? [], isLimited: value?["limited"] as? Bool ?? false)
    }

    func apply(_ updates: [Update], token: String) async throws -> Int {
        try await perform("apply", token: token, texts: updates.map(\.text), indices: updates.map(\.index)) as? Int
            ?? 0
    }

    func restore(token: String) async throws {
        _ = try await perform("restore", token: token)
    }

    private func perform(
        _ action: String, token: String = "", texts: [String] = [], indices: [Int] = []
    ) async throws -> Any? {
        try await evaluate(
            BrowserTranslationJavaScript.source,
            ["action": action, "token": token, "texts": texts, "offset": 0, "indices": indices]
        )
    }
}
