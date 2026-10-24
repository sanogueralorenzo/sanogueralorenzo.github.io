import Observation

/// Whether agents can reach this launch of Crest now, which Settings shows:
/// whether the socket listens, and why there is none while agents are on and
/// the socket could not open. `BrowserMacAgents` keeps it current.
@MainActor
@Observable
final class BrowserAgentEndpointStatus {
    // MARK: - Types

    enum State: Equatable {
        /// No socket listens, as while agents are off.
        case closed
        /// Agents' helpers can connect.
        case listening
        /// Agents are on but the socket could not open.
        case failed(BrowserAgentListener.Failure)
    }

    // MARK: - Variables

    var state = State.closed
}
