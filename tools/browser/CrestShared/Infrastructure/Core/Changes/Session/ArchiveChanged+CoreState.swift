import Foundation

extension ArchiveChanged {
    @MainActor func apply(to state: CoreState) {
        if let space = state.space(spaceID, in: workspaceID) {
            let gone = Set(removed)
            state.favicons.detach(removed)
            state.favicons.place(
                archived.map(\.tab.id).filter { !space.archive.contains(tabID: $0) || gone.contains($0) },
                in: workspaceID)
            space.apply(self)
        }
        state.touch(workspaceID)
    }
}
