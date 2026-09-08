import Foundation

enum RewriteProvider: String, CaseIterable {
    case openai = "OpenAI", anthropic = "Anthropic"
    var providerID: String { self == .openai ? "openai-codex" : "anthropic" }
    var notice: String { "Uses your Pi sign-in. Selected text is sent to \(rawValue)." }
    var preferredModel: String { self == .openai ? "gpt-5.6-luna" : "claude-haiku-4-5-20251001" }
    static func saved(_ value: String?) -> RewriteProvider? {
        switch value {
        case "Codex CLI": return .openai
        case "Claude CLI": return .anthropic
        default: return value.flatMap(Self.init(rawValue:))
        }
    }
    var modelLabel: String { self == .openai ? "GPT 5.6 Luna · Reasoning off · Priority" : "Claude Haiku 4.5 · Thinking off" }
}

struct RewriteConfiguration: Equatable {
    let kind: RewriteProvider
    var resolvedModel: String { kind.preferredModel }
    var thinking: String { "off" }
}

