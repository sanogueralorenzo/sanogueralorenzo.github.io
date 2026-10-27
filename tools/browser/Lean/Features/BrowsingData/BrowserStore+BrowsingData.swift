import Foundation

extension BrowserStore {
    func restore(_ entry: BrowserArchiveEntry) {
        let spaceID = session.spaces.contains(where: { $0.id == entry.spaceID }) ? entry.spaceID : activeSpace.id
        var tab = entry.tab
        tab.id = UUID()
        tab.folderID = nil
        session.spaces[spaceIndex(spaceID)].tabs.append(tab)
        session.archive.removeAll { $0.id == entry.id }
        selectTab(tab.id)
    }

    func pageFinished(_ page: BrowserPage) {
        pageChanged(page)
        guard !session.spaces.contains(where: { $0.id == page.spaceID && $0.isPrivate }),
            let url = page.url, ["https", "http"].contains(url.scheme ?? "")
        else { return }
        let count = session.history.first { $0.spaceID == page.spaceID && $0.url == url }?.count ?? 0
        session.history.removeAll { $0.spaceID == page.spaceID && $0.url == url }
        var visit = BrowserVisit(spaceID: page.spaceID, title: page.title, url: url)
        visit.count = count + 1
        session.history.insert(visit, at: 0)
        changed()
    }

    func clearHistory() {
        session.history.removeAll { $0.spaceID == activeSpace.id }
        changed()
    }

    func reopenClosedTab() {
        if let entry = session.archive.first(where: { $0.spaceID == activeSpace.id }) { restore(entry) }
    }
}
