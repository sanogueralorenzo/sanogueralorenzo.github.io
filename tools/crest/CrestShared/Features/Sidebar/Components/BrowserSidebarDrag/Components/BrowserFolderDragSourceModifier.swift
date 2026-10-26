import SwiftUI

struct BrowserFolderDragSourceModifier: ViewModifier {
    let folder: FolderStateModel
    let profileID: UUID
    let spaceID: UUID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [UUID]? = nil
    var reorder: BrowserSidebarReorderContext?
    let isEnabled: Bool
    var requiresSelectedSpace = false

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    @ViewBuilder
    func body(content: Content) -> some View {
        let isEnabled = SidebarSpaceRole.permitsInteraction(
            isSelected: requiresSelectedSpace ? isSelected : nil, isAvailable: self.isEnabled)
        let item = BrowserFolderDragItem(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: memberTabIDs
        )
        let isDragging = isEnabled && reorder == nil && dragState.isDragging(item)
        content
            .modifier(BrowserDragSourceLiftStyle(isDragging: isDragging))
            .modifier(
                BrowserPlatformFolderDragSourceModifier(
                    folder: folder,
                    profileID: profileID,
                    spaceID: spaceID,
                    dragState: dragState,
                    memberTabIDs: memberTabIDs,
                    reorder: reorder,
                    isEnabled: isEnabled
                )
            )
    }
}
