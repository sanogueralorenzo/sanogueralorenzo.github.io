import SwiftUI

struct BrowserTabDragSourceModifier: ViewModifier {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let spaceID: UUID
    let dragState: BrowserTabDragState
    var reorder: BrowserSidebarReorderContext?
    var parentSplitGroupID: UUID?
    var isEnabled = true
    var requiresSelectedSpace = false

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    @ViewBuilder
    func body(content: Content) -> some View {
        let isEnabled = SidebarSpaceRole.permitsInteraction(
            isSelected: requiresSelectedSpace ? isSelected : nil, isAvailable: self.isEnabled)
        let item = BrowserTabDragItem(
            tabID: tab.id,
            spaceID: spaceID,
            profileID: profileID
        )
        let isDragging = isEnabled && reorder == nil && dragState.isDragging(item)
        content
            .modifier(BrowserDragSourceLiftStyle(isDragging: isDragging))
            .modifier(
                BrowserPlatformTabDragSourceModifier(
                    tab: tab,
                    favicons: favicons,
                    profileID: profileID,
                    spaceID: spaceID,
                    dragState: dragState,
                    reorder: reorder,
                    parentSplitGroupID: parentSplitGroupID,
                    isEnabled: isEnabled
                )
            )
    }
}
