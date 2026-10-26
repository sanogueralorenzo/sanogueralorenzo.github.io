import Foundation

extension SyncJournalChanged {
    /// The journal changed. A stage reached it, so the last failure no longer
    /// stands.
    @MainActor func apply(to state: CoreState) {
        state.syncJournal = self
        state.syncStagingFailure = nil
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        core.syncJournalChangeHandler?()
    }
}
