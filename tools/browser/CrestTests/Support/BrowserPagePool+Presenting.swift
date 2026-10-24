import Foundation

@testable import Crest

extension BrowserPagePool {
    /// Shows tab `tabID` of Space `spaceID` in the pool's window, then
    /// presents what the window shows, for a test that moves between tabs.
    func present(tab tabID: UUID, in spaceID: UUID, at time: Date = .now) {
        browser.selectSpace(spaceID)
        browser.selectTab(tabID)
        select(at: time)
    }
}
