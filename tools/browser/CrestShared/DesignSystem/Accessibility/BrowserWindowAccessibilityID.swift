import Foundation

enum BrowserWindowAccessibilityID {
    static func scene(_ id: UUID) -> String {
        BrowserAccessibilityID.identifier(
            prefix: "browser-window",
            id: id
        )
    }
}
