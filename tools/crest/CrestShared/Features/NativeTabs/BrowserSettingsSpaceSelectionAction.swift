import Foundation

@MainActor
struct BrowserSettingsSpaceSelectionAction {
    let browser: BrowserStore

    @discardableResult
    func select(_ id: UUID, matching source: BrowserTabRuntimeAssignment) -> BrowserTabRuntimeAssignment? {
        guard
            let sourceSpace = browser.selectedAvailableSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)),
            sourceSpace.tabs.model(source.tabID)?.nativeTabContent == .settings,
            let destination = browser.availableSpaces.first(where: { $0.id == id })
        else { return nil }

        browser.selectSpace(id)
        guard let tabID = browser.openSettings() else { return nil }
        return BrowserTabRuntimeAssignment(tabID: tabID, spaceID: destination.id, profileID: destination.profileID)
    }
}
