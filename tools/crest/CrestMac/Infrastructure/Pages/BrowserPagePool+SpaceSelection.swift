import Foundation

extension BrowserPagePool {
    // MARK: - Actions - Space Selection

    /// Entering a Space restores resident cards, but does not open its
    /// remembered unloaded tabs on the person's behalf.
    func selectSpace(in browser: BrowserStore) {
        guard let space = browser.shownSpace else {
            deactivatePagePresentation()
            return
        }
        guard let tab = browser.shownTab else {
            leavePagePresentation()
            return
        }
        if browser.consumeMovedTabActivation() {
            select()
        } else if requiresStartPageOnEntry(to: space) {
            browser.presentStartPageForSpaceEntry()
            leavePagePresentation()
        } else if tab.surface == .startPage && browser.cards(in: space).count < 2 {
            leavePagePresentation()
        } else {
            select()
        }
    }

    /// The retained content strip asks the same question as selection, without
    /// creating a tab or starting a navigation while preparing a neighbor:
    /// whether a card the window shows in `space` is a web page with no
    /// resident page.
    func requiresStartPageOnEntry(to space: SpaceModel) -> Bool {
        browser.cards(in: space).contains { card in
            card.surface == .webPage
                && !containsResidentPage(
                    matching: BrowserTabRuntimeAssignment(tabID: card.id, spaceID: space.id, profileID: space.profileID)
                )
        }
    }

    /// Each Space owns one content surface in the retained strip. A resident
    /// page may be drawn there before activation, but it cannot own focus or
    /// input until selection commits. Locked surfaces never mount live pages.
    func surfacePage(
        for tabID: UUID, in space: SpaceModel, accessController: BrowserSpaceAccessController
    ) -> BrowserPage? {
        guard !accessController.isLocked(space), browser.cards(in: space).contains(where: { $0.id == tabID }) else {
            return nil
        }
        return residentPage(
            matching: BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
    }
}
