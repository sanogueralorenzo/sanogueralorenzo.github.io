import Foundation
import WebKit

struct BrowserBrowsingDataTarget: Identifiable {
    let id: UUID
    let name: String
}

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

    func presentClearBrowsingData(in spaceID: UUID) {
        guard !isClosed, let space = session.spaces.first(where: { $0.id == spaceID }) else { return }
        clearingBrowsingData = BrowserBrowsingDataTarget(id: space.id, name: space.name)
    }

    func clearBrowsingData(
        in spaceID: UUID, since cutoff: Date, history: Bool, websiteData: Bool, cache: Bool
    ) async {
        guard !isClosed, session.spaces.contains(where: { $0.id == spaceID }) else { return }
        if history, session.removeVisits(in: spaceID, where: { $0 >= cutoff }) {
            changed()
        }
        guard websiteData || cache else { return }
        let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        var types = websiteData ? WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes) : []
        if cache { types.formUnion(cacheTypes) }
        await profile(for: spaceID).removeData(ofTypes: types, modifiedSince: cutoff)
        if !isClosed { showNotice(websiteData ? "Website data cleared" : "Cache cleared") }
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
        session.recordVisit(to: url, in: page.spaceID, title: page.title)
        changed()
    }
}

extension BrowserSession {
    mutating func recordVisit(to url: URL, in spaceID: UUID, title: String, at date: Date = Date()) {
        var visit = BrowserVisit(spaceID: spaceID, title: title, url: url, date: date)
        if let index = history.firstIndex(where: { $0.spaceID == spaceID && $0.url == url }) {
            visit = history.remove(at: index)
            visit.earlierDates = (visit.earlierDates ?? []) + [visit.date]
            visit.date = date
            visit.title = title
        }
        history.insert(visit, at: 0)
    }

    mutating func removeVisits(in spaceID: UUID, where shouldRemove: (Date) -> Bool) -> Bool {
        var removed = false
        let remaining = history.compactMap { entry -> BrowserVisit? in
            guard entry.spaceID == spaceID else { return entry }
            var visit = entry
            visit.earlierDates?.removeAll(where: shouldRemove)
            if shouldRemove(visit.date) {
                removed = true
                guard let earlier = visit.earlierDates?.popLast() else { return nil }
                visit.date = earlier
                visit.title = visit.url.absoluteString
            }
            if visit.earlierDates?.isEmpty == true { visit.earlierDates = nil }
            removed = removed || visit.count != entry.count
            return visit
        }
        if removed { history = remaining.sorted { $0.date > $1.date } }
        return removed
    }
}
