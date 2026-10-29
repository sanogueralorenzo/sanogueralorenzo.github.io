import Foundation

extension DownloadDestinationAsked: CorePromptChange {
    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
