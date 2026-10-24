import SwiftUI

struct PinnedTabOrganizationMenu: View {
    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    let isLoaded: Bool
    let dragState: BrowserTabDragState?
    let renameTab: () -> Void
    let changeIcon: () -> Void

    var body: some View {
        BrowserTabOrganizationMenu(
            tab: tab,
            context: context,
            assignment: assignment,
            isLoaded: isLoaded,
            renameTab: renameTab,
            changeIcon: changeIcon
        )
        .tint(.primary)
        .onAppear { dragState?.contextMenuDidOpen(for: assignment) }
        .onDisappear { dragState?.contextMenuDidClose(for: assignment) }
    }
}
