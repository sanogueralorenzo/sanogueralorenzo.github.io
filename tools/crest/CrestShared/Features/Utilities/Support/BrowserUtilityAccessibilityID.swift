import Foundation

/// Stable identifiers for the shared Archive, History, and Downloads surfaces.
enum BrowserUtilityAccessibilityID {
    static func list(_ surface: BrowserUtilitySurface) -> String {
        "\(component(for: surface))-utility-list"
    }

    static func destination(_ surface: BrowserUtilitySurface) -> String {
        "utility-destination-\(component(for: surface))"
    }

    static func historyRow(_ id: UUID) -> String {
        "history-utility-row-\(id.uuidString.lowercased())"
    }

    static func downloadRow(_ id: UUID) -> String {
        "downloads-utility-row-\(id.uuidString.lowercased())"
    }

    private static func component(for surface: BrowserUtilitySurface) -> String {
        surface.name
    }
}
