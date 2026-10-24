import SwiftUI

struct PinnedTabDragModifier: ViewModifier {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let assignment: BrowserSpaceRuntimeAssignment
    let dragState: BrowserTabDragState?
    var reorder: BrowserSidebarReorderContext?

    func body(content: Content) -> some View {
        if let reorder, let dragState {
            content
                .browserTabDraggable(
                    tab: tab,
                    favicons: favicons,
                    profileID: assignment.profileID,
                    spaceID: assignment.spaceID,
                    dragState: dragState,
                    reorder: reorder
                )
        } else {
            content
        }
    }
}
