import Foundation

extension FoldersChanged {
    @MainActor func apply(to state: CoreState) {
        state.space(spaceID, in: workspaceID)?.apply(self)
        state.touch(workspaceID)
    }
}
