import Foundation

// MARK: - Snapshots

struct MobileBrowserRootLockSnapshot: Equatable, Sendable {
    let sessionRevision: BrowserSessionRevision
    let selectedSpaceID: UUID
    let selectedProfileID: UUID?
    let isLocked: Bool
    let presentation: MobileBrowserPresentation
}

struct MobileBrowserRootSelectionSnapshot: Equatable, Sendable {
    let sessionRevision: BrowserSessionRevision
    let selectedSpaceID: UUID
    let selectedProfileID: UUID?
    let assignment: BrowserTabRuntimeAssignment?
}
