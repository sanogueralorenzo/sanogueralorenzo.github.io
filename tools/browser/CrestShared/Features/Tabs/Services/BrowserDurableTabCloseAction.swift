import Foundation

/// Puts a saved or pinned tab's page away, as closing it does. The core asks
/// the page whether it may go first, then records the close, which returns
/// the tab to its saved address when the app's preferences say so; the page
/// host of the window that asked follows it and lets the page go.
@MainActor
struct BrowserDurableTabCloseAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// False when the tab is not a saved or pinned tab of an unlocked Space
    /// this window shows, or its page may not go yet.
    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        let space = BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID)
        guard
            let unlocked = browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess),
            unlocked.tabs.model(assignment.tabID)?.placement.isDurable == true
        else { return false }
        return browser.performPageDismissal(of: [assignment]) {
            guard
                browser.selectedUnlockedSpace(matching: space, accessController: spaceAccess) != nil
            else { return false }
            return browser.closeDurableTab(assignment)
        }
    }
}
