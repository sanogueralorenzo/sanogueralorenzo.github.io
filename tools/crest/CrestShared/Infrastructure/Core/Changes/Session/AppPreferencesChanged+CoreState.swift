import Foundation

extension AppPreferencesChanged {
    @MainActor func apply(to state: CoreState) {
        state.workspaces[workspaceID]?.apply(self)
        state.touch(workspaceID)
    }
}
