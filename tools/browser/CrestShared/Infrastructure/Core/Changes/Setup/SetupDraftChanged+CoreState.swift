import Foundation

extension SetupDraftChanged {
    /// The core publishes the manual setup whole, or nil once it ends.
    @MainActor func apply(to state: CoreState) {
        state.setupDraft = draft
    }
}
