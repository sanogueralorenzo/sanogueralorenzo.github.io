import Foundation

extension ImportFlowChanged {
    /// The core publishes setup whole, or nil once it ends.
    @MainActor func apply(to state: CoreState) {
        state.importFlow = flow
    }
}
