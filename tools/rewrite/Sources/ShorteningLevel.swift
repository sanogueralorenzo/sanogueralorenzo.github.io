import Foundation

enum ShorteningLevel: String, CaseIterable {
    case light = "Light"
    case balanced = "Balanced"
    case strong = "Strong"

    var menuTitle: String {
        switch self {
        case .light: return "Light · ~10% shorter"
        case .balanced: return "Balanced · ~30% shorter"
        case .strong: return "Strong · ~50% shorter"
        }
    }

    var promptInstruction: String {
        switch self {
        case .light:
            return "Use a light edit: tighten wording modestly, usually around 10% shorter when the text allows it. Do not force cuts that harm clarity."
        case .balanced:
            return "Use a balanced edit: aim for around 30% fewer words when the text allows it, while keeping the message natural and complete."
        case .strong:
            return "Use a strong edit: aim for around 50% fewer words when the text allows it, keeping only wording and context that materially help the message."
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: "conciseness").flatMap(Self.init(rawValue:)) ?? .light
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "conciseness")
    }
}
