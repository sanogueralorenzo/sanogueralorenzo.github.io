import Foundation

extension RemoveEngineDownload {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.downloads.remove(downloadID)
    }
}
