import SwiftUI

@MainActor
enum BrowserSidebarDensityPreference {
    static let defaults = BrowserFolderAppearancePreference.defaults
    static let scaleKey = "crest.appearance.tabScale"
    static let pinColumnsKey = "crest.appearance.pinColumns"
    static let pinsFillRowKey = "crest.appearance.pinsFillRow"

    static func number(_ key: String, default fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.double(forKey: key)
        return value.isFinite ? value : fallback
    }
}
