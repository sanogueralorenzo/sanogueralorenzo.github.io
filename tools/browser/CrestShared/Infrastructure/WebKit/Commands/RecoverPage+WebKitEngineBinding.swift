import Foundation

extension RecoverPage {
    /// WebKit starts a new web content process for the page's current
    /// history entry.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.page(pageID)?.webView.reload()
    }
}
