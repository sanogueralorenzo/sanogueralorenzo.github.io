import Foundation

/// Each session change updates the workspace it names and the images its tabs
/// wear. The images move first, while the read model still holds what the
/// change replaces, so a tab a change places anew is told apart from one it
/// keeps. Each change also marks its workspace's session changed, which the
/// workspace announces once the batch is applied.
extension CoreState {
    // MARK: - Actions - Images

    /// The images the platform kept for the tabs of a workspace that opened
    /// before they were offered, as the persistent session a launch loads
    /// does: each tab the workspace holds that wears none takes its own.
    func adoptImages(_ images: [UUID: Data], in workspaceID: UUID) {
        guard let workspace = workspaces[workspaceID] else { return }
        let held = Set(workspace.tabIDs)
        favicons.adopt(images) { held.contains($0) }
    }

    // MARK: - Actions - Batches

    /// A batch of changes was applied: images of tabs a change removed and no
    /// workspace holds any longer are gone, and each workspace whose session
    /// a change changed announces it, with the images kept beside the core's
    /// file following that session.
    func finishBatch() {
        favicons.finishBatch { tabID in workspaces.values.contains { $0.holds(tabID: tabID) } }
        for workspace in workspacesStorage.values where workspace.finishBatch() {
            favicons.keepImages(of: workspace)
        }
    }

    // MARK: - Actions - Changes

    func space(_ spaceID: UUID, in workspaceID: UUID) -> SpaceModel? {
        workspaces[workspaceID]?.spaces.model(spaceID)
    }

    /// Every tab a Space holds, open or archived.
    static func tabIDs(of space: SpaceState) -> [UUID] {
        space.tabs.map(\.id) + space.archivedTabs.map(\.tab.id)
    }

    func touch(_ workspace: UUID) {
        workspacesStorage[workspace]?.sessionChanged()
    }
}
