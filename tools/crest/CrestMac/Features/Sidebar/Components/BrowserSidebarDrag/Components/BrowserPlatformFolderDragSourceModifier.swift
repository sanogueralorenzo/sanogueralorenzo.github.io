import SwiftUI

struct BrowserPlatformFolderDragSourceModifier: ViewModifier {
    let folder: FolderStateModel
    let profileID: UUID
    let spaceID: UUID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [UUID]? = nil
    var reorder: BrowserSidebarReorderContext?
    var isEnabled = true

    private var item: BrowserFolderDragItem {
        BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: memberTabIDs
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            // Folders reorder in place among their siblings, on the same path as
            // tabs. See `BrowserSidebarReorderState` for why AppKit's dragging
            // session is not used.
            content
                .browserSidebarReorderSource(
                    item: .folder(item),
                    section: folder.reorderSection,
                    reorder: reorder,
                    registersContainer: false,
                    isEnabled: isEnabled
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
