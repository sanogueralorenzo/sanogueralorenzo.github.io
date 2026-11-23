import Foundation

extension BrowserStore {
    func restore(_ entry: BrowserArchiveEntry) {
        guard !isClosed, let entry = session.archive.first(where: { $0.id == entry.id }) else { return }
        let spaceID = session.spaces.contains(where: { $0.id == entry.spaceID }) ? entry.spaceID : activeSpace.id
        guard canChangeTabCount(by: 1, in: spaceID) else { return }
        var tab = entry.tab
        tab.id = UUID()
        tab.folderID = nil
        var candidate = session
        let index = spaceIndex(spaceID)
        if tab.placement == .pinned && !candidate.spaces[index].canAddPins(1) {
            tab.placement = .saved
            tab.savedURL = tab.savedURL ?? tab.url
        }
        candidate.spaces[index].tabs.append(tab)
        candidate.archive.removeAll { $0.id == entry.id }
        guard (try? candidate.validate()) != nil else {
            showNotice("This tab couldn’t be restored. Its archived copy has been kept.")
            return
        }
        session = candidate
        selectTab(tab.id)
    }

    func clearHistory() {
        session.history.removeAll { $0.spaceID == activeSpace.id }
        changed()
    }

    func reopenClosedTab() {
        if let entry = session.archive.first(where: { $0.spaceID == activeSpace.id }) { restore(entry) }
    }
}

extension BrowserSessionOwner {
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
}
