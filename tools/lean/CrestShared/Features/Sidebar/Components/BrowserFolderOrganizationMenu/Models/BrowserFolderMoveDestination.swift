import Foundation

struct BrowserFolderMoveDestination: Identifiable {
    let folder: FolderStateModel
    let path: String

    var id: UUID { folder.id }
}
