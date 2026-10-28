import Foundation

extension CloseReady {
    /// A close preparation's end and its question about downloads in progress
    /// change no model: `CrestCore.prepareToClose` hears the end, and the
    /// question's presenter follows prompts.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.closesReady.append(self)
    }
}
