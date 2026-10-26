import Foundation

@testable import CrestMobile

extension MobileBrowserPageStore {
    /// Shows tab `tabID` of Space `spaceID` in the store's scene, then
    /// presents what the scene shows, for a test that moves between tabs.
    func present(tab tabID: UUID, in spaceID: UUID, at time: Date = .now) {
        browser.selectSpace(spaceID)
        browser.selectTab(tabID)
        select(at: time)
    }

    /// Shows Space `spaceID` in the store's scene on the tab it last showed
    /// there, then presents what the scene shows.
    func present(space spaceID: UUID, at time: Date = .now) {
        browser.selectSpace(spaceID)
        select(at: time)
    }
}
