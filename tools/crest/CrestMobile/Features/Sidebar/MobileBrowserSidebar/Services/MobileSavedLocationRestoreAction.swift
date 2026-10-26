import Foundation

@MainActor
struct MobileSavedLocationRestoreAction {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let selectTab: (UUID) -> Void
    var spaceAccess = BrowserSpaceAccessController()

    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.shownSpace,
            space.id == assignment.spaceID,
            space.profileID == assignment.profileID,
            !spaceAccess.isLocked(space),
            space.tabs.contains(assignment.tabID),
            browser.returnsToSavedAddress(assignment.tabID, in: space.id),
            !pages.containsResidentPage(for: assignment.tabID) || pages.containsResidentPage(matching: assignment)
        else { return false }

        let hadResidentPage = pages.containsResidentPage(matching: assignment)
        pages.discardArchivedTabState(matching: assignment)
        guard let url = browser.restoreTabSavedLocation(assignment.tabID, in: assignment.spaceID)
        else { return false }
        selectTab(assignment.tabID)
        let pageActions = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            expectedAssignment: assignment
        )
        guard let page = pageActions.activePage
        else { return false }
        if hadResidentPage && page.live.pendingNavigationURL != url { page.corePage.load(url) }
        return true
    }
}
