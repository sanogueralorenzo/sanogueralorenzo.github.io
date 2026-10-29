import Foundation

extension DownloadApprovalAsked: CorePromptChange {
    @MainActor func apply(to state: CoreState) {}

    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
