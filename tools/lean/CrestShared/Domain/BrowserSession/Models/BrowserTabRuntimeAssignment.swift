import Foundation

struct BrowserTabRuntimeAssignment: Equatable, Hashable, Sendable {
    let tabID: UUID
    let spaceID: UUID
    let profileID: UUID

    /// Where the tab's Space lives: its identity and profile.
    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }
}
