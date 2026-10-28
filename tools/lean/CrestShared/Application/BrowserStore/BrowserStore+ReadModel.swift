import Foundation

/// Where this window's workspace, its Spaces and what the window shows live
/// in the read model. Each lookup observes only what it names: the workspace
/// list, one Space's membership, or the window list.
extension BrowserStore {
    // MARK: - Actions - Reading

    /// This window's workspace in the read model, or nil once the device no
    /// longer holds it.
    var workspaceModel: WorkspaceModel? {
        core.state.workspaces[family.workspaceID]
    }

    /// What this window shows in the read model, or nil once it closed,
    /// even when another window opened under its identity since.
    var windowModel: WindowStateModel? {
        isClosed ? nil : core.state.windows[windowID]
    }

    /// A Space of this window's workspace in the read model.
    func spaceModel(_ spaceID: UUID) -> SpaceModel? {
        workspaceModel?.spaces.model(spaceID)
    }
}
