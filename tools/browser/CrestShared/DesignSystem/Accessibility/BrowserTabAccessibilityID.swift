import Foundation

enum BrowserTabAccessibilityID {
    static func row(_ id: UUID) -> String {
        BrowserAccessibilityID.identifier(prefix: "tab", id: id)
    }

    static func archivedRow(_ id: UUID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "archived-tab",
            id: id
        )
    }
}
