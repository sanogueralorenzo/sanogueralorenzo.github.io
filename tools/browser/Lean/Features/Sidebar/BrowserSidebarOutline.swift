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
    var pinnedTabs: [BrowserTab] {
        let pins = Dictionary(uniqueKeysWithValues: tabs.filter { $0.placement == .pinned }.map { ($0.id, $0) })
        return orderedSidebarIDs.compactMap { pins[$0] }
    }

    var sidebarItemIDs: [UUID] {
        var result = pinnedTabs.map(\.id)
        func append(_ parent: UUID?, _ placement: BrowserTab.Placement) {
            for entry in sidebarEntries(parentID: parent, placement: placement) {
                result.append(entry.id)
                if case .folder(let folder) = entry.kind { append(folder.id, placement) }
            }
        }
        append(nil, .saved)
        append(nil, .current)
        return result
    }

    var orderedSidebarIDs: [UUID] {
        let all = folders.map(\.id) + tabs.map(\.id)
        let available = Set(all)
        var seen = Set<UUID>()
        let order = ((sidebarOrderIDs ?? []) + all).filter { available.contains($0) && seen.insert($0).inserted }
        let groups = Dictionary(
            uniqueKeysWithValues: splits.flatMap { split in
                split.tabIDs.map { ($0, split.tabIDs) }
            })
        return order.flatMap { id in
            guard let group = groups[id] else { return [id] }
            return group.first == id ? group : []
        }
    }
    func folderPath(to tabID: UUID) -> Set<UUID> {
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var path = Set<UUID>()
        var parent = tabs.first { $0.id == tabID }?.folderID
        while let id = parent, path.insert(id).inserted { parent = byID[id]?.parentID }
        return path
    }

    func sidebarEntries(parentID: UUID?, placement: BrowserTab.Placement, keeping: UUID? = nil) -> [BrowserSidebarEntry]
    {
        let path = keeping.map(folderPath(to:))
        let keptTabs = keeping.map { id in Set(splits.first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]) }
        let folders = Dictionary(
            uniqueKeysWithValues: folders.filter {
                $0.parentID == parentID && ($0.placement ?? .saved) == placement
                    && (path?.contains($0.id) ?? true)
            }.map { ($0.id, $0) })
        let tabs = Dictionary(
            uniqueKeysWithValues: tabs.filter {
                $0.folderID == parentID && $0.placement == placement
                    && (keptTabs?.contains($0.id) ?? true)
            }.map { ($0.id, $0) })
        return orderedSidebarIDs.compactMap { id in
            if let folder = folders[id] { return BrowserSidebarEntry(id: id, kind: .folder(folder)) }
            if let tab = tabs[id] { return BrowserSidebarEntry(id: id, kind: .tab(tab)) }
            return nil
        }
    }

    mutating func reorderSidebarItems(_ ids: [UUID], before: UUID?) {
        guard !ids.contains(before ?? UUID()) else { return }
        let all = orderedSidebarIDs
        let available = Set(all)
        var seen = Set<UUID>()
        let moving = ids.filter { available.contains($0) && seen.insert($0).inserted }
        var remaining = all.filter { !ids.contains($0) }
        let destination = before.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
        remaining.insert(contentsOf: moving, at: destination)
        sidebarOrderIDs = remaining
    }
}

extension BrowserStore {
    func reorderSidebarItems(_ ids: [UUID], in spaceID: UUID, before: UUID?) {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        session.spaces[index].reorderSidebarItems(ids, before: before)
    }
}
