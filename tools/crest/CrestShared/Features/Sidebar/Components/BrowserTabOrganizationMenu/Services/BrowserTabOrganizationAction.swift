import Foundation

@MainActor
struct BrowserTabOrganizationAction {
    let browser: BrowserStore

    func linkURL(for assignment: BrowserTabRuntimeAssignment) -> URL? {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID, profileID: assignment.profileID)
        guard
            let space = browser.selectedAvailableSpace(matching: spaceAssignment),
            let tab = space.tabs.model(assignment.tabID), tab.surface == .webPage
        else { return nil }
        return browser.tabLinkProvider?.liveLinkURL(for: assignment) ?? tab.address
    }

    @discardableResult
    func copyLinkURL(for assignment: BrowserTabRuntimeAssignment) -> Bool {
        BrowserPageLinkClipboard.copy(linkURL(for: assignment))
    }

    @discardableResult
    func close(
        _ assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> Bool {
        guard !expectedPlacement.isDurable,
            let spaceAssignment = liveSpaceAssignment(
                for: assignment,
                expectedPlacement: expectedPlacement
            )
        else { return false }
        return browser.closeTab(assignment.tabID, matching: spaceAssignment)
    }

    @discardableResult
    func delete(
        _ assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> Bool {
        guard expectedPlacement.isDurable,
            let spaceAssignment = liveSpaceAssignment(
                for: assignment,
                expectedPlacement: expectedPlacement
            )
        else { return false }
        return browser.deleteTab(assignment.tabID, matching: spaceAssignment)
    }

    private func liveSpaceAssignment(
        for assignment: BrowserTabRuntimeAssignment,
        expectedPlacement: TabPlacement
    ) -> BrowserSpaceRuntimeAssignment? {
        let spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        guard
            let space = browser.selectedAvailableSpace(matching: spaceAssignment),
            let tab = space.tabs.model(assignment.tabID),
            tab.placement == expectedPlacement
        else { return nil }
        return spaceAssignment
    }
}
