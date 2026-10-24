import Foundation

/// The content blocking each Space of a workspace chose.
struct BrowserContentBlockingSessionState: Equatable, Sendable {
    let policiesBySpaceID: [UUID: ContentBlockingPolicy]

    init(policiesBySpaceID: [UUID: ContentBlockingPolicy]) {
        self.policiesBySpaceID = policiesBySpaceID
    }

    /// What each Space of `workspace` in the read model chose.
    @MainActor
    init(workspace: WorkspaceModel?) {
        self.init(
            policiesBySpaceID: Dictionary(
                uniqueKeysWithValues: (workspace?.spaces.models ?? []).map { space in
                    (space.id, space.settings.browsingPreferences.contentBlocking)
                }))
    }
}
