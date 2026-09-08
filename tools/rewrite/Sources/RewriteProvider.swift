import Foundation

enum RewriteProvider: String, CaseIterable {
    case openai = "OpenAI", anthropic = "Anthropic"
    var providerID: String { self == .openai ? "openai-codex" : "anthropic" }
    var preferredModel: String { self == .openai ? "gpt-5.6-luna" : "claude-haiku-4-5-20251001" }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        saved(defaults.string(forKey: "processor")) ?? .openai
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "processor")
    }
    static func saved(_ value: String?) -> RewriteProvider? {
        switch value {
        case "Codex CLI": return .openai
        case "Claude CLI": return .anthropic
        default: return value.flatMap(Self.init(rawValue:))
        }
    }
}
