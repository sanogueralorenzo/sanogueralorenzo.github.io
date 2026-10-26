import Foundation

extension DownloadDestinationAsked: CorePromptChange {
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.prompts.append(self)
    }

    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
