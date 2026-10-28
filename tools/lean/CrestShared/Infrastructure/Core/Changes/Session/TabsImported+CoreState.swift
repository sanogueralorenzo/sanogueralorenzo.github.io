import Foundation

extension TabsImported {
    @MainActor func apply(to state: CoreState) {
        if let workspace = state.workspaces[workspaceID] {
            state.favicons.place(imported: tabs.filter { workspace.holds(tabID: $0.tabID) }, in: workspaceID)
        }
        state.touch(workspaceID)
    }
}
