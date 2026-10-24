import Foundation

/// Where the person interacted while a utility list was open, and whether that
/// puts the list away.
struct BrowserUtilityInteractionSurface: Equatable, Sendable {
    // MARK: - Static Variables

    static let webContent = BrowserUtilityInteractionSurface(name: "webContent", dismissesUtilities: true)
    static let sidebarBlankSpace = BrowserUtilityInteractionSurface(name: "sidebarBlankSpace", dismissesUtilities: true)
    /// A control keeps the list open.
    static let control = BrowserUtilityInteractionSurface(name: "control", dismissesUtilities: false)

    // MARK: - Variables

    let name: String
    let dismissesUtilities: Bool
}
