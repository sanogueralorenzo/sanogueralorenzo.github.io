import Foundation

enum Provider: String, CaseIterable {
    case openai, anthropic
    var label: String {
        switch self {
        case .openai: "OpenAI · Luna"
        case .anthropic: "Anthropic · Haiku"
        }
    }
    static func load(from url: URL) throws -> Provider? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .openai }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let values = object as? [String: Any], let saved = values["provider"] as? String else { return nil }
        switch saved {
        case "codex": return .openai
        case "claude": return .anthropic
        default: return Provider(rawValue: saved) // Former Local/unknown settings require an explicit choice.
        }
    }
    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(["provider": rawValue]).write(to: url, options: .atomic)
    }
}
