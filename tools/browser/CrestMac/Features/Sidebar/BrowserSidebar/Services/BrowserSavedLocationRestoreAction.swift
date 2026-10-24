import Foundation

/// Sends a tab that has wandered back to the location it was saved at.
///
/// This is the one sidebar row action the shells cannot share: it needs the
/// page that is on screen right now, and the two shells find that page in
/// different places — this one in the window's card pool, the compact shell
/// through its own selected-page port.
@MainActor
struct BrowserSavedLocationRestoreAction {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    /// Updates the tab before selection so an unloaded page starts at its root.
    /// A resident page keeps its native history. A tab already home with no
    /// navigation away, or outside the selected unlocked Space, is left alone.
    @discardableResult
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                ), accessController: spaceAccess),
            let tab = space.tabs.model(assignment.tabID),
            browser.returnsToSavedAddress(tab.id, in: space.id),
            !pages.containsResidentPage(for: tab.id) || pages.containsResidentPage(matching: assignment)
        else { return false }
        let hadResidentPage = pages.containsResidentPage(matching: assignment)
        pages.discardArchivedTabState(matching: assignment)
        guard let url = browser.restoreTabSavedLocation(assignment.tabID, in: assignment.spaceID)
        else { return false }
        browser.selectTab(assignment.tabID)
        pages.select()
        guard let page = pages.activePage(matching: assignment)
        else { return false }
        if hadResidentPage && page.live.pendingNavigationURL != url { page.corePage.load(url) }
        return true
    }
}
