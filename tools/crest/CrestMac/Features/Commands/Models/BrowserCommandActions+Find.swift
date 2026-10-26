import SwiftUI

extension BrowserCommandActions {
    // MARK: - Variables

    /// Utility search can accept Find even when its window has no page supporting text search.
    var canFind: Bool {
        canSearchUtility || commandPageSupports(.find)
    }

    /// Search is available only in this window's visible utility and an unlocked Space.
    private var canSearchUtility: Bool {
        guard chrome.utilityPresentation.surface != nil,
            chrome.columnVisibility != .detailOnly || chrome.isFloatingSidebarPresented,
            let space = browser.shownSpace, !spaceAccess.isLocked(space)
        else { return false }
        return true
    }

    // MARK: - Actions - Find

    /// Routes native Find input to eligible utility search, otherwise to the command page.
    func presentFind() {
        if canSearchUtility {
            chrome.utilityPresentation.focusSearch()
        } else {
            commandPage?.presentFind()
        }
    }
}
