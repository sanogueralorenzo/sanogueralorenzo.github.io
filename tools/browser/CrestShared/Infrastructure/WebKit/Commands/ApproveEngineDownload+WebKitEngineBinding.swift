import Foundation

extension ApproveEngineDownload {
    /// WebKit warns about nothing itself, so the only download the core
    /// approves is a blocked one the person retried.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.downloads.approve(downloadID)
    }
}
