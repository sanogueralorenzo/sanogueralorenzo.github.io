import Foundation

extension TabCopied {
    @MainActor func apply(to state: CoreState) {
        if state.workspaces[workspaceID]?.holdsOpen(tabID: copyTabID) == true {
            state.favicons.copy(sourceTabID, to: copyTabID, in: workspaceID)
        }
        state.touch(workspaceID)
    }
}
