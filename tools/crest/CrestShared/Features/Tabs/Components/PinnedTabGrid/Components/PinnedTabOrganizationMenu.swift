import SwiftUI

struct PinnedTabOrganizationMenu: View {
    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    let dragState: BrowserTabDragState?
    let renameTab: () -> Void

    var body: some View {
        BrowserTabOrganizationMenu(
            tab: tab,
            context: context,
            assignment: assignment,
            renameTab: renameTab
        )
        .tint(.primary)
        .onAppear { dragState?.contextMenuDidOpen(for: assignment) }
        .onDisappear { dragState?.contextMenuDidClose(for: assignment) }
    }
}
