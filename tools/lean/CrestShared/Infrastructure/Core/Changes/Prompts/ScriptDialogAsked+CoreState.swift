import Foundation

extension ScriptDialogAsked: CorePromptChange {
    /// A question waiting on the person changes no model: `CrestCore` hands it
    /// to the engine whose page shows it, and the person's answer goes back
    /// to the core as an intent.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.prompts.append(self)
    }

    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
