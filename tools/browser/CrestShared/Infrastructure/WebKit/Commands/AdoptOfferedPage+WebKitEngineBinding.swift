import Foundation

extension AdoptOfferedPage {
    /// The page the core adopted is the popup WebKit made for the page that
    /// offered it, built from the configuration WebKit derived from its
    /// opener's, so its first navigation stays WebKit's own. The page that
    /// offered it hands its web view to WebKit, and the page's owner hosts it.
    /// An offer that no longer waits fails.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let engines = binding.engines, let offer = binding.offers[offerID] else {
            binding.report(PageCreationFailed(pageID: pageID))
            return
        }
        let creation = CreatePage(
            pageID: pageID, profileID: profileID, isPrivate: isPrivate, windowID: windowID, restoreState: nil)
        let page = binding.keep(binding.build(creation, in: offer.space, popup: offer.popup))
        binding.adoptedOffers[offerID] = page
        engines.handOver(page, adoptedPage: pageID)
        binding.report(PageCreated(pageID: pageID))
    }
}
