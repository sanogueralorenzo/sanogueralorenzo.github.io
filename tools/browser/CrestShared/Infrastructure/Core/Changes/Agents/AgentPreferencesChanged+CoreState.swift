import Foundation

extension AgentPreferencesChanged {
    @MainActor func apply(to state: CoreState) {
        state.agentPreferences = preferences
    }
}
