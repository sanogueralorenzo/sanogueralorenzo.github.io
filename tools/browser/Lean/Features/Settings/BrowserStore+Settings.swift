import Foundation

extension BrowserStore {
    func openSettings() {
        if let tab = activeSpace.tabs.first(where: \.isSettings) {
            selectTab(tab.id)
            return
        }
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
