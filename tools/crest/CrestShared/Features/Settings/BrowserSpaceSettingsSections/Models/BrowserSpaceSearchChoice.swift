import Foundation

/// What a Space may search with, as its picker offers it: the device's
/// default search, which it then follows, or one search engine or AI
/// assistant of its own.
struct BrowserSpaceSearchChoice: Identifiable, Hashable {
    // MARK: - Variables

    /// The Space's own provider, or nil to follow the default.
    let provider: SearchProvider?

    var id: String { provider?.name ?? "" }
}

/// Whether a Space suggests searches, as its picker offers it: as the
/// device's default does, which it then follows, or on or off of its own.
struct BrowserSpaceSuggestionChoice: Identifiable, Hashable {
    // MARK: - Static Variables

    static let followsDefault = BrowserSpaceSuggestionChoice(enabled: nil)
    static let on = BrowserSpaceSuggestionChoice(enabled: true)
    static let off = BrowserSpaceSuggestionChoice(enabled: false)

    static let all = [followsDefault, on, off]

    // MARK: - Variables

    /// The Space's own choice, or nil to follow the default.
    let enabled: Bool?

    var id: String { enabled.map(String.init) ?? "" }

    // MARK: - Actions - Presentation

    /// What the picker says for the choice, naming what the default does now.
    func title(defaultEnabled: Bool) -> String {
        guard let enabled else {
            return defaultEnabled
                ? String(
                    localized: "Default (On)", comment: "A Space follows the default search suggestions, which are on.")
                : String(
                    localized: "Default (Off)",
                    comment: "A Space follows the default search suggestions, which are off.")
        }
        return enabled ? String(localized: "On") : String(localized: "Off")
    }
}
