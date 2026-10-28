import Foundation

extension BrowserStore {
    func openSettings() {
        guard !isClosed else { return }
        if let tab = activeSpace.tabs.first(where: \.isSettings) {
            selectTab(tab.id)
            return
        }
        guard canChangeTabCount(by: 1, in: activeSpace.id) else { return }
        var tab = BrowserTab()
        tab.title = "Settings"
        tab.isSettings = true
        let index = spaceIndex(activeSpace.id)
        session.spaces[index].tabs.append(tab)
        selectTab(tab.id)
    }

    func updatePreferences(_ update: (inout BrowserPreferences) -> Void) {
        let blocked = preferences.blocksContent
        update(&session.preferences)
        if blocked != preferences.blocksContent {
            reloadContentBlocking()
        }
        changed()
    }
}
