import Foundation

enum BrowserAddressTarget {
    case newTab, tab(UUID), split(UUID)

    var splitSource: UUID? {
        if case .split(let id) = self { return id }
        return nil
    }
}

extension BrowserStore {
    func presentAddress(newTab: Bool = false) {
        if !newTab, let tab = selectedTab, !tab.isSettings {
            presentAddress(target: .tab(tab.id), text: tab.url?.absoluteString ?? "")
        } else {
            presentAddress(target: .newTab)
        }
    }

    func presentAddress(target: BrowserAddressTarget, text: String = "") {
        addressPresentationID = UUID()
        if !sidebarDocked { sidebarRevealed = false }
        utility = nil
        addressText = text
        addressTarget = target
    }

    func submitAddress(_ text: String) {
        guard let url = preferences.searchProvider.resolve(text) else { return }
        submitAddress(url)
    }

    func submitAddress(_ url: URL) {
        switch addressTarget {
        case .newTab:
            if open(url) != nil { dismissAddress() }
        case .tab(let id):
            dismissAddress()
            if selectedTab?.id == id { navigate(url, in: id) }
        case .split(let source):
            if openSplit(url, beside: source) { dismissAddress() }
        case nil: break
        }
    }

    func dismissAddress() {
        addressTarget = nil
    }
}
