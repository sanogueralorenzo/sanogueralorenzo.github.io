import Foundation

extension Saved {
    @MainActor func apply(to state: CoreState) {
        state.savedRevision = max(state.savedRevision, revision)
        state.storageFailure = nil
    }
}
