import Observation
import WebKit

/// Reconciles the workspace's protection choices against WebKit's uBOL profiles.
@MainActor
@Observable
final class BrowserContentBlockingController {
    // MARK: - Variables

    @ObservationIgnored private let blocking: WebKitContentBlocking
    @ObservationIgnored private var reconciledState: BrowserContentBlockingSessionState?

    /// Why protection could not start, when startup failed.
    var errorDescription: String? { blocking.errorDescription }

    // MARK: - Initializers

    /// Shares WebKit's runtime while retaining this owner's reconciliation state.
    init(blocking: WebKitContentBlocking?) {
        self.blocking = blocking ?? WebKitContentBlocking()
    }

    // MARK: - Actions - Protection

    func prepare() async {
        await blocking.prepare()
    }

    /// Prepares protection when needed and answers
    /// what changed since the last reconciliation.
    func reconcile(in workspace: WorkspaceModel?) async -> BrowserContentBlockingUpdate {
        let state = BrowserContentBlockingSessionState(workspace: workspace)
        if state.policiesBySpaceID.values.contains(where: \.blocksContent) {
            await prepare()
        }
        let update = BrowserContentBlockingUpdate(state: state, previousState: reconciledState)
        reconciledState = state
        return update
    }

}
