import Foundation

enum ShorteningLevel: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case strong = "Strong"
    case maximum = "Maximum"

    var menuTitle: String {
        switch self {
        case .light: return "Light · ~10% shorter"
        case .medium: return "Medium · ~25% shorter"
        case .strong: return "Strong · ~40% shorter"
        case .maximum: return "Maximum · ~55% shorter"
        }
    }

    var sliderIndex: Int {
        Self.allCases.firstIndex(of: self)!
    }

    static func atSliderIndex(_ index: Int) -> Self {
        allCases[min(max(index, 0), allCases.count - 1)]
    }

    var promptInstruction: String {
        switch self {
        case .light:
            return "Use a light edit: tighten wording modestly, usually around 10% shorter when the text allows it. Do not force cuts that harm clarity."
        case .medium:
            return "Use a moderate edit: aim for around 25% fewer words when the text allows it, while keeping the message natural and complete."
        case .strong:
            return "Use a strong edit: aim for around 40% fewer words when the text allows it, keeping only wording and context that materially help the message."
        case .maximum:
            return "Use a very strong edit: aim for around 55% fewer words when the text allows it, keeping the essential meaning, facts, and context."
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let saved = defaults.string(forKey: "conciseness") ?? defaults.string(forKey: "shortening")
        return saved.flatMap(Self.init(rawValue:)) ?? .light
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "conciseness")
    }
}
