import Foundation

struct BrowserSidebarEntry: Identifiable {
    enum Kind {
        case folder(BrowserFolder)
        case tab(BrowserTab)
    }
    let id: UUID
    let kind: Kind
}

extension BrowserSpace {
    var orderedSidebarIDs: [UUID] {
        let all = folders.map(\.id) + tabs.map(\.id)
        let available = Set(all)
        var seen = Set<UUID>()
        return ((sidebarOrderIDs ?? []) + all).filter { available.contains($0) && seen.insert($0).inserted }
    }
    func sidebarEntries(parentID: UUID?, placement: BrowserTab.Placement) -> [BrowserSidebarEntry] {
        let folders = Dictionary(
            uniqueKeysWithValues: folders.filter {
                $0.parentID == parentID && ($0.placement ?? .saved) == placement
            }.map { ($0.id, $0) })
        let tabs = Dictionary(
            uniqueKeysWithValues: tabs.filter {
                $0.folderID == parentID && $0.placement == placement
            }.map { ($0.id, $0) })
        return orderedSidebarIDs.compactMap { id in
            if let folder = folders[id] { return BrowserSidebarEntry(id: id, kind: .folder(folder)) }
            if let tab = tabs[id] { return BrowserSidebarEntry(id: id, kind: .tab(tab)) }
            return nil
        }
    }
}

extension BrowserStore {
    func reorderSidebarItems(_ ids: [UUID], in spaceID: UUID, before: UUID?) {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }), !ids.contains(before ?? UUID()) else {
            return
        }
        let all = session.spaces[index].orderedSidebarIDs
        let moving = all.filter(ids.contains)
        var remaining = all.filter { !ids.contains($0) }
        let destination = before.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
        remaining.insert(contentsOf: moving, at: destination)
        session.spaces[index].sidebarOrderIDs = remaining
    }
}
