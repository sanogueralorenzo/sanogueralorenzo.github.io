import Foundation

extension CancelEngineDownload {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.downloads.cancel(downloadID)
    }
}
