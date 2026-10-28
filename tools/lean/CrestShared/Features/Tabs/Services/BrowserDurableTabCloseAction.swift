import Foundation

/// Puts a saved or pinned tab's page away, as closing it does. The core asks
/// the page whether it may go first, then records the close, preserving the
/// tab's last location and page state; the page
/// host of the window that asked follows it and lets the page go.
@MainActor
struct BrowserDurableTabCloseAction {
    let browser: BrowserStore

    func perform(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        let space = BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID)
        guard
            let unlocked = browser.selectedAvailableSpace(matching: space),
            unlocked.tabs.model(assignment.tabID)?.placement.isDurable == true
        else { return false }
        return browser.performPageDismissal(of: [assignment]) {
            guard
                browser.selectedAvailableSpace(matching: space) != nil
            else { return false }
            return browser.closeDurableTab(assignment)
        }
    }
}
