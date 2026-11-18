import Foundation

extension BrowserStore {
    func presentAddress(newTab: Bool = false) {
        addressPresentationID = UUID()
        sidebarRevealed = false
        pendingSplitSourceID = nil
        utility = nil
        addressCreatesTab = newTab || selectedTab == nil || selectedTab?.isSettings == true
        addressText = addressCreatesTab ? "" : selectedTab?.url?.absoluteString ?? ""
        addressPresented = true
    }

    func submitAddress(_ text: String) {
        guard let url = preferences.searchProvider.resolve(text) else { return }
        submitAddress(url)
    }

    func submitAddress(_ url: URL) {
        if addressCreatesTab || selectedTab == nil {
            let source = pendingSplitSourceID
            guard let id = open(url) else { return }
            addressPresented = false
            pendingSplitSourceID = nil
            if let source { split(source, with: id) }
        } else if let id = selectedTab?.id {
            addressPresented = false
            navigate(url, in: id)
        }
    }

    func dismissAddress() {
        addressPresented = false
        pendingSplitSourceID = nil
    }
}
