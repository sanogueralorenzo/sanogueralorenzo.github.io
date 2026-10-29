import Foundation

extension DownloadApprovalAsked: CorePromptChange {
    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
