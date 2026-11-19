import Foundation

/// The page adapter supplies evaluation in an isolated translation world.
@MainActor
struct BrowserTranslationDocument {

    /// The evaluator returns nil if the document is gone.
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

    private let evaluate: Evaluate

    init(evaluate: @escaping Evaluate) {
        self.evaluate = evaluate
    }

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
