import Foundation

extension WorkspaceClosed {
    @MainActor func apply(to state: CoreState) {
        if let workspace = state.workspacesStorage[workspaceID] {
            state.favicons.detach(workspace.tabIDs)
            state.publish(nil, forKey: workspaceID, into: \.workspacesStorage, as: \.workspaces)
        }
        state.touch(workspaceID)
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
    }
}
