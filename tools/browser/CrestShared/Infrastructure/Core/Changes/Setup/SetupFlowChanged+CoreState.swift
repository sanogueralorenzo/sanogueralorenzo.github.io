import Foundation

extension SetupFlowChanged {
    /// The core publishes setup whole, or nil once it ends.
    @MainActor func apply(to state: CoreState) {
        state.setupFlow = flow
    }
}
