import Foundation

/// A native document uses the tab's existing identity, placement, and card layout.
/// The stable kind remains decodable when another build adds a new native view.
/// Resource IDs refer to separately stored documents; view closures and runtime
/// state never enter the session or CloudKit payload.
struct BrowserNativeTabContent: Codable, Equatable, Hashable, Sendable {
    let kind: String
    var resourceID: UUID? = nil

    static let settings = Self(kind: NativeView.settings.name)
    static let gettingStarted = Self(kind: NativeView.gettingStarted.name)
}
