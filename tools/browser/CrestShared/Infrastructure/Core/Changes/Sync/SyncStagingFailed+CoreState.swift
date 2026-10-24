import Foundation

extension SyncStagingFailed {
    @MainActor func apply(to state: CoreState) {
        state.syncStagingFailure = reason
    }
}
