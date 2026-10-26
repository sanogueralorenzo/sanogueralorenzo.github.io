import Foundation

struct BrowserFolderRuntimeAssignment: Equatable, Hashable, Sendable {
    let folderID: UUID
    let spaceID: UUID
    let profileID: UUID

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
    }
}
