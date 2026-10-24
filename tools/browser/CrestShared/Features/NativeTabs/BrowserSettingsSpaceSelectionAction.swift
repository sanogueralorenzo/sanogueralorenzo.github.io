import Foundation

@MainActor
struct BrowserSettingsSpaceSelectionAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @discardableResult
    func select(_ id: UUID, matching source: BrowserTabRuntimeAssignment) -> BrowserTabRuntimeAssignment? {
        guard
            let sourceSpace = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                accessController: spaceAccess),
            sourceSpace.tabs.model(source.tabID)?.nativeTabContent == .settings,
            let destination = browser.availableSpaces.first(where: { $0.id == id }),
            !spaceAccess.isLocked(destination)
        else { return nil }

        browser.selectSpace(id)
        guard let tabID = browser.openSettings() else { return nil }
        return BrowserTabRuntimeAssignment(tabID: tabID, spaceID: destination.id, profileID: destination.profileID)
    }
}
