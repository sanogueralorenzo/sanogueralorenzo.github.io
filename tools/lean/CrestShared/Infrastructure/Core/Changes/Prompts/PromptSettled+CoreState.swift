import Foundation

extension PromptSettled: CorePromptChange {
    @MainActor func present(on host: any CorePromptHost) {
        host.dismiss(self)
    }
}
