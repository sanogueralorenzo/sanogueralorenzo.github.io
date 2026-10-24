import SwiftUI

/// Whether Crest draws its windows light, dark, or as the system does at the
/// moment, which follows the system as it changes through the day.
struct BrowserAppearanceMode: Hashable, Sendable {
    // MARK: - Static Variables

    static let system = BrowserAppearanceMode(name: "system", title: "System", colorScheme: nil)
    static let light = BrowserAppearanceMode(name: "light", title: "Light", colorScheme: .light)
    static let dark = BrowserAppearanceMode(name: "dark", title: "Dark", colorScheme: .dark)
    static let all = [system, light, dark]
    static let standard = system

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// The scheme every window draws in, or nil to follow the system.
    let colorScheme: ColorScheme?

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, colorScheme: ColorScheme?) {
        self.name = name
        self.title = title
        self.colorScheme = colorScheme
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserAppearanceMode? {
        all.first { $0.name == name }
    }
}

// MARK: - Hashable

extension BrowserAppearanceMode {
    static func == (lhs: BrowserAppearanceMode, rhs: BrowserAppearanceMode) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
