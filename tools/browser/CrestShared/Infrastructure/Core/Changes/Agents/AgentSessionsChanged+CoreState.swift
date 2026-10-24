import Foundation

extension AgentSessionsChanged {
    @MainActor func apply(to state: CoreState) {
        state.agentSessions = sessions
    }
}
