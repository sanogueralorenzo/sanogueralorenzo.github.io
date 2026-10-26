import SwiftUI

extension View {
    func browserTabDraggable(
        tab: TabStateModel,
        favicons: FaviconAssets,
        profileID: UUID,
        spaceID: UUID,
        dragState: BrowserTabDragState,
        reorder: BrowserSidebarReorderContext? = nil,
        parentSplitGroupID: UUID? = nil,
        isEnabled: Bool = true,
        requiresSelectedSpace: Bool = false
    ) -> some View {
        modifier(
            BrowserTabDragSourceModifier(
                tab: tab,
                favicons: favicons,
                profileID: profileID,
                spaceID: spaceID,
                dragState: dragState,
                reorder: reorder,
                parentSplitGroupID: parentSplitGroupID,
                isEnabled: isEnabled,
                requiresSelectedSpace: requiresSelectedSpace
            )
        )
    }

    /// - Parameter members: the run behind this row, for platforms that draw
    ///   their own lift preview. macOS lifts the row itself and passes nothing.
    func browserSplitGroupDraggable(
        item: BrowserSplitGroupDragItem,
        members: [TabStateModel] = [],
        favicons: FaviconAssets? = nil,
        placement: TabPlacement,
        folderID: UUID?,
        reorder: BrowserSidebarReorderContext? = nil,
        isEnabled: Bool = true,
        requiresSelectedSpace: Bool = false
    ) -> some View {
        modifier(
            BrowserSplitGroupDragSourceModifier(
                item: item,
                members: members,
                favicons: favicons,
                placement: placement,
                folderID: folderID,
                reorder: reorder,
                isEnabled: isEnabled,
                requiresSelectedSpace: requiresSelectedSpace
            )
        )
    }

    func browserFolderDraggable(
        folder: FolderStateModel,
        profileID: UUID,
        spaceID: UUID,
        dragState: BrowserFolderDragState,
        memberTabIDs: [UUID]? = nil,
        reorder: BrowserSidebarReorderContext? = nil,
        isEnabled: Bool = true,
        requiresSelectedSpace: Bool = false
    ) -> some View {
        modifier(
            BrowserFolderDragSourceModifier(
                folder: folder,
                profileID: profileID,
                spaceID: spaceID,
                dragState: dragState,
                memberTabIDs: memberTabIDs,
                reorder: reorder,
                isEnabled: isEnabled,
                requiresSelectedSpace: requiresSelectedSpace
            )
        )
    }
}
