import Foundation

extension TabsChanged {
    @MainActor func apply(to state: CoreState) {
        if let space = state.space(spaceID, in: workspaceID) {
            let gone = Set(removed)
            state.favicons.detach(removed)
            state.favicons.place(
                updated.map(\.id).filter { !space.tabs.contains($0) || gone.contains($0) },
                in: workspaceID)
            space.apply(self)
        }
        state.touch(workspaceID)
    }
}
