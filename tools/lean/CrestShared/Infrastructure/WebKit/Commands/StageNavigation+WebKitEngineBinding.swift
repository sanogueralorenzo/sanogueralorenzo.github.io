import Foundation

extension StageNavigation {
    /// Makes the link the core staged the first load of its page; one that no
    /// longer applies is reported, so the page does not load it as a bare
    /// address.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let link = binding.stagedLinks.removeValue(forKey: stagedLinkID),
            let page = binding.page(pageID), link.request.url?.absoluteString == url,
            page.engine.stage(link.request)
        else {
            binding.report(StagedLinkUnavailable(pageID: pageID))
            return
        }
    }
}
