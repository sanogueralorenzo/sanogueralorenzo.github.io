import Foundation

extension SetupCompletedChanged {
    @MainActor func apply(to state: CoreState) {
        state.setupCompleted = completed
    }
}
