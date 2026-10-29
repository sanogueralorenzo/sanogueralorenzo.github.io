import Foundation

extension QuitWithDownloadsAsked: CorePromptChange {
    @MainActor func present(on host: any CorePromptHost) {
        host.ask(self)
    }
}
