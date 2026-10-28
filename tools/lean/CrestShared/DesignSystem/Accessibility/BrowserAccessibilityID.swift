import Foundation

/// Stable accessibility identifiers derived from domain identity, never mutable
/// or localized display text.
enum BrowserAccessibilityID {

    static func identifier(prefix: String, id: UUID) -> String {
        "\(prefix)-\(id.uuidString.lowercased())"
    }

}
