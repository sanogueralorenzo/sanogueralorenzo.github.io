import Foundation

extension SettleDownloadDestination {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.downloads.settle(self)
    }
}
