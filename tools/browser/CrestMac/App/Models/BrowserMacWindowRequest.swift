import Foundation

/// A browser window to open, by its identity in the core; the application
/// owns the workspace it shows.
struct BrowserMacWindowRequest: Hashable, Identifiable {
    // MARK: - Static Variables

    /// The initial normal browser window, whose identity stays the same
    /// across launches.
    static let initial = BrowserMacWindowRequest(
        // 3A92C7E8-46F1-4D55-86BB-0F226747F8D1
        id: UUID(
            uuid: (
                0x3A, 0x92, 0xC7, 0xE8,
                0x46, 0xF1,
                0x4D, 0x55,
                0x86, 0xBB,
                0x0F, 0x22, 0x67, 0x47, 0xF8, 0xD1
            )),
        kind: .normal)

    // MARK: - Types

    enum Kind { case normal, temporary }

    // MARK: - Variables

    let id: UUID
    let kind: Kind
    var sourceWindowID: UUID?
    var sourceAssignment: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    static func normal(sourceWindowID: UUID?) -> Self {
        Self(id: UUID(), kind: .normal, sourceWindowID: sourceWindowID)
    }

    static func temporary(sourceWindowID: UUID?, assignment: BrowserSpaceRuntimeAssignment) -> Self {
        Self(
            id: UUID(), kind: .temporary,
            sourceWindowID: sourceWindowID, sourceAssignment: assignment)
    }

    /// The request a normal window kept under `id` reopens with.
    static func reopening(_ id: UUID) -> Self {
        id == initial.id ? initial : Self(id: id, kind: .normal)
    }
}
