import Foundation

struct BrowserRuntimeSessionProjection: Equatable, Sendable {
    // MARK: - Variables

    let tabIconState: BrowserTabIconSessionState
    let contentBlockingState: BrowserContentBlockingSessionState

    // MARK: - Initializers

    /// What `workspace` in the read model holds now, its tabs wearing the
    /// icons `images` keeps.
    @MainActor
    init(workspace: WorkspaceModel?, images: FaviconAssets) {
        tabIconState = BrowserTabIconSessionState(workspace: workspace, images: images)
        contentBlockingState = BrowserContentBlockingSessionState(workspace: workspace)
    }
}
