import Foundation

/// Keeps a Quick Window's or Peek's page as a tab. The core checks both Spaces
/// and whether the tab may take the live page; the adapter moves it when this
/// platform can.
struct BrowserTransientPagePromotion {
    /// The transient page, or nil when there is none to keep.
    let page: CorePage?
    /// Where the page is, or nil when it has not been anywhere worth keeping.
    let url: URL?
    let destinationAssignment: BrowserSpaceRuntimeAssignment
    /// Whether this platform can move the live page into the tab's window.
    var supportsLiveAdoption = true

    enum Outcome {
        case adoptedLivePage
        case openedNewPage
        case selectedSpace
    }

    /// Keeps the page, or with no address to keep only shows the destination
    /// Space. `adoptPage` moves the live page into the new tab.
    @MainActor
    func perform(
        in browser: BrowserStore,
        isLocked: @MainActor (SpaceModel) -> Bool,
        adoptPage: (UUID, SpaceModel) -> Bool
    ) -> Outcome? {
        guard let destination = browser.spaceModel(matching: destinationAssignment) else { return nil }
        guard url != nil else {
            guard !isLocked(destination) else { return nil }
            browser.selectSpace(destination.id)
            return .selectedSpace
        }
        guard let page, let promoted = browser.promoteTransientPage(page, into: destination.id),
            let currentDestination = browser.spaceModel(matching: destinationAssignment)
        else { return nil }
        let adoptedLivePage =
            supportsLiveAdoption && promoted.adoptsPage
            && adoptPage(promoted.tabID, currentDestination)
        return adoptedLivePage ? .adoptedLivePage : .openedNewPage
    }
}
