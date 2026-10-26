import Foundation

extension SpacesChanged {
    @MainActor func apply(to state: CoreState) {
        if let workspace = state.workspaces[workspaceID] {
            for spaceID in removed { state.favicons.detach(workspace.spaces.model(spaceID)?.tabIDs ?? []) }
            state.favicons.place(added.flatMap(CoreState.tabIDs), in: workspaceID)
            workspace.apply(self)
        }
        state.touch(workspaceID)
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
    }
}
