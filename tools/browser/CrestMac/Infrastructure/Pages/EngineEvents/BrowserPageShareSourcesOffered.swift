/// A document in the page asked to share the screen; the person chooses one
/// of the offer's tabs, or a window or display.
struct BrowserPageShareSourcesOffered: BrowserPageEngineEvent {
    // MARK: - Variables

    let offer: BrowserShareSourceOffer

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        // A new request replaces one the person has not answered, which is
        // refused.
        if let previous = page.shareSourceOffer, previous.id != offer.id {
            page.enginePage.chooseShareSource(previous.id, choice: .cancel)
        }
        page.shareSourceOffer = offer
    }
}
