import Foundation

/// A native page report edits its tab and history together. Reports for a gone tab are ignored.
extension SessionMutations {
    func pageRecord(_ request: some Intent) throws -> SessionMutation? {
        let spaceID: UUID
        let tabID: UUID?
        switch request {
        case let value as RecordPageNavigation: (spaceID, tabID) = (value.spaceID, value.tabID)
        case let value as RecordPageTitle: (spaceID, tabID) = (value.spaceID, value.tabID)
        case let value as RecordPageIcon: (spaceID, tabID) = (value.spaceID, value.tabID)
        default: return nil
        }
        guard var original = basis.space(id: spaceID), !basis.spaceDeletions.contains(where: { $0.spaceID == spaceID })
        else { return nil }
        let index = tabID.flatMap { id in original.tabs.firstIndex { $0.id == id } }
        if tabID != nil && index == nil { return nil }
        var effects: [any CoreChange] = []
        func appearance(_ index: Int, address: String?, title: String?) {
            if let address {
                original.tabs[index].url = address
                original.tabs[index].nativeContent = nil
            }
            if let title, !title.isEmpty { original.tabs[index].title = title }
        }
        func icon(_ index: Int, address: String, accent: TabIconAccent?, page: UUID) {
            guard original.tabs[index].resolved.iconMode.followsPage else { return }
            original.tabs[index].symbol = TabIconMode.webSymbol
            original.tabs[index].faviconURL = address
            original.tabs[index].iconAccent = accent
            effects.append(
                TabFaviconAssigned(workspaceID: workspaceID, tabID: original.tabs[index].id, adopts: true, pageID: page)
            )
        }
        switch request {
        case let value as RecordPageNavigation:
            if let index {
                appearance(index, address: value.url, title: value.title)
                if value.hasIcon { icon(index, address: value.url, accent: value.iconAccent, page: value.pageID) }
            }
            original.history = SessionHistory.visiting(
                original.history, address: value.url, title: value.title, at: value.at, id: value.visitID)
            effects.append(
                NavigationRecorded(
                    pageID: value.pageID, workspaceID: workspaceID, spaceID: spaceID, tabID: value.tabID, url: value.url
                ))
        case let value as RecordPageTitle:
            if let index, let shown = original.tabs[index].url, PageAddress.samePage(shown, value.url) {
                appearance(index, address: nil, title: value.title)
            }
            if value.visit {
                original.history = SessionHistory.retitling(original.history, address: value.url, title: value.title)
            }
        case let value as RecordPageIcon:
            if let index, let shown = original.tabs[index].url, PageAddress.samePage(shown, value.url) {
                icon(index, address: value.url, accent: value.accent, page: value.pageID)
            }
        default: preconditionFailure("Unrecognized page report")
        }
        return replacing([original], stage: .pageReport, effects: effects)
    }
}

enum SessionHistory {
    static func visiting(_ history: [HistoryEntryState], address: String, title: String?, at now: Date, id: UUID)
        -> [HistoryEntryState]
    {
        guard let url = BrowserWebAddress.normalized(address),
            BrowserWebAddress.normalized(url).map({ Data($0.utf8) }) == Data(url.utf8)
        else { return history }
        let previous = history.first { Data($0.url.utf8) == Data(url.utf8) }
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? previous?.title ?? BrowserWebAddress.host(url) ?? url
        let visit = HistoryEntryState(
            id: previous?.id ?? id, url: url, title: name.isEmpty ? url : name,
            firstVisitedAt: previous?.firstVisitedAt ?? now, lastVisitedAt: now,
            visitCount: (previous?.visitCount ?? 0) + 1)
        return [visit] + history.filter { $0.id != visit.id }.prefix(SessionValidation.maximumHistory - 1)
    }
    static func retitling(_ history: [HistoryEntryState], address: String, title: String) -> [HistoryEntryState] {
        guard !title.isEmpty, let url = BrowserWebAddress.normalized(address),
            let entry = history.first(where: { Data($0.url.utf8) == Data(url.utf8) }),
            Data(entry.title.utf8) != Data(title.utf8)
        else { return history }
        return history.map { value in
            value.id == entry.id
                ? HistoryEntryState(
                    id: value.id, url: value.url, title: title, firstVisitedAt: value.firstVisitedAt,
                    lastVisitedAt: value.lastVisitedAt, visitCount: value.visitCount) : value
        }
    }
}
