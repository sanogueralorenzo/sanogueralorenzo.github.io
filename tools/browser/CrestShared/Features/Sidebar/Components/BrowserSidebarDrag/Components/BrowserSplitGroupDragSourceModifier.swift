import SwiftUI

/// The header starts a group drag using the enclosing container's measurements.
struct BrowserSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// The run this row stands for. Only the platform that draws its own lift
    /// preview reads it; the identities the commit needs travel in `item`.
    var members: [TabStateModel] = []
    var favicons: FaviconAssets? = nil
    let placement: TabPlacement
    let folderID: UUID?
    var reorder: BrowserSidebarReorderContext?
    var isEnabled = true
    var requiresSelectedSpace = false

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    @ViewBuilder
    func body(content: Content) -> some View {
        let isEnabled = SidebarSpaceRole.permitsInteraction(
            isSelected: requiresSelectedSpace ? isSelected : nil, isAvailable: self.isEnabled)
        if let reorder {
            content
                .modifier(
                    BrowserPlatformSplitGroupDragSourceModifier(
                        item: item,
                        members: members,
                        favicons: favicons,
                        placement: placement,
                        folderID: folderID,
                        reorder: reorder,
                        isEnabled: isEnabled
                    )
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
