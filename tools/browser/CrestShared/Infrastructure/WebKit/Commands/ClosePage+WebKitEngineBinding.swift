import Foundation

extension ClosePage {
    /// WebKit requires an answer to every question the page asked, and the
    /// page takes the links it staged with it.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let engines = binding.engines else { return }
        let page = binding.pages.removeValue(forKey: pageID)?.value
        binding.declinePrompts(of: pageID)
        binding.stagedLinks = binding.stagedLinks.filter { $0.value.sourcePageID != pageID }
        engines.report(PageClosed(pageID: pageID, restoreState: keepsState ? page?.restoreState : nil), from: binding)
    }
}
