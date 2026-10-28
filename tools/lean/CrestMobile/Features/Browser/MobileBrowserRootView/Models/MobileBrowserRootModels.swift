import Foundation

// MARK: - Snapshots

struct MobileBrowserRootSelectionSnapshot: Equatable, Sendable {
    let sessionRevision: BrowserSessionRevision
    let selectedSpaceID: UUID
    let selectedProfileID: UUID?
    let assignment: BrowserTabRuntimeAssignment?
}
