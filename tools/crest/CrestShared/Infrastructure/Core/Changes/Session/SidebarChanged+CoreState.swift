import Foundation

extension SidebarChanged {
    /// The sidebar's lists are the read model's alone: windows need not
    /// follow them.
    @MainActor func apply(to state: CoreState) {
        state.space(spaceID, in: workspaceID)?.apply(self)
    }
}
