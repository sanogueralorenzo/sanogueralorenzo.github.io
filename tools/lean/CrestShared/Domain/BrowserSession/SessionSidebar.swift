import Foundation

/// Builds sidebar rows from session values, including empty-folder anchors and split runs.
struct SessionSidebar {
    let outline: SidebarOutline
    private struct Node {
        let folder: FolderState.Seed
        let depth: Int
    }
    private struct Item {
        let id: UUID
        let kind: SidebarRowKind
        let folder: UUID?
        let members: [UUID]
    }

    init(tabs: [TabState.Seed], folders: [FolderState.Seed]) {
        var nodes: [Node] = []
        var known: Set<UUID> = []
        let unique = folders.filter { known.insert($0.id).inserted }
        var visited: Set<UUID> = []
        func append(_ folder: FolderState.Seed, depth: Int) {
            guard depth < FolderState.maximumDepth, visited.insert(folder.id).inserted else { return }
            nodes.append(Node(folder: folder, depth: depth))
            for child in unique where child.parentID == folder.id { append(child, depth: depth + 1) }
        }
        for folder in unique where folder.parentID == nil { append(folder, depth: 0) }
        var insides: [UUID: [SidebarRow]] = [:]
        var lists: [SidebarList] = []
        for section in TabPlacement.all {
            let listed = tabs.filter { $0.placement == section && !SessionTabs.isStartPage($0) }
            let items = Self.fold(listed, splits: section.holdsSplits)
            let top =
                section.holdsFolders
                ? Self.nest(section, items: items, listed: listed, nodes: nodes, insides: &insides)
                : items.map { SidebarRow(id: $0.id, kind: $0.kind, parentFolderID: nil, depth: 0, members: $0.members) }
            lists.append(SidebarList(section: section, folderID: nil, rows: top))
        }
        for folder in unique {
            lists.append(SidebarList(section: folder.location, folderID: folder.id, rows: insides[folder.id] ?? []))
        }
        outline = SidebarOutline(lists: lists)
    }
    private static func fold(_ tabs: [TabState.Seed], splits: Bool) -> [Item] {
        var items: [Item] = []
        var folded: Set<UUID> = []
        var index = 0
        while index < tabs.count {
            let tab = tabs[index]
            guard splits, let group = tab.splitGroupID, !folded.contains(group) else {
                items.append(Item(id: tab.id, kind: .tab, folder: tab.folderID, members: [tab.id]))
                index += 1
                continue
            }
            var end = index + 1
            while end < tabs.count && tabs[end].splitGroupID == group { end += 1 }
            if end - index >= SidebarOutline.minimumSplitMembers {
                items.append(Item(id: group, kind: .split, folder: tab.folderID, members: tabs[index..<end].map(\.id)))
                folded.insert(group)
            } else {
                for member in tabs[index..<end] {
                    items.append(Item(id: member.id, kind: .tab, folder: member.folderID, members: [member.id]))
                }
            }
            index = end
        }
        return items
    }
    private static func nest(
        _ section: TabPlacement, items: [Item], listed: [TabState.Seed], nodes: [Node],
        insides: inout [UUID: [SidebarRow]]
    ) -> [SidebarRow] {
        var byID: [UUID: Node] = [:]
        var paths: [UUID: [UUID]] = [:]
        for node in nodes where node.folder.location == section {
            byID[node.folder.id] = node
            paths[node.folder.id] = (node.folder.parentID.flatMap { paths[$0] } ?? []) + [node.folder.id]
        }
        var top: [SidebarRow] = []
        func add(_ row: SidebarRow, inside parent: UUID?) {
            if let parent { insides[parent, default: []].append(row) } else { top.append(row) }
        }
        func folderRow(_ node: Node, parent: UUID?) -> SidebarRow {
            SidebarRow(id: node.folder.id, kind: .folder, parentFolderID: parent, depth: node.depth, members: [])
        }
        var reached: Set<UUID> = []
        for item in items {
            let path: [UUID]
            if let folder = item.folder {
                guard let found = paths[folder] else { continue }
                path = found
            } else {
                path = []
            }
            var above: UUID?
            for id in path {
                if reached.insert(id).inserted { add(folderRow(byID[id]!, parent: above), inside: above) }
                above = id
            }
            add(
                SidebarRow(
                    id: item.id, kind: item.kind, parentFolderID: item.folder,
                    depth: item.folder.map { byID[$0]!.depth + 1 } ?? 0, members: item.members), inside: item.folder)
        }
        for node in nodes where node.folder.location == section && !reached.contains(node.folder.id) {
            let folder = node.folder
            if let parent = folder.parentID, byID[parent] == nil { continue }
            var rows = folder.parentID.map { insides[$0] ?? [] } ?? top
            var insertion = rows.count
            if let anchor = folder.orderAnchorTabID {
                let path = listed.first { $0.id == anchor }?.folderID.flatMap { paths[$0] } ?? []
                insertion =
                    rows.firstIndex { $0.kind.opensList ? path.contains($0.id) : $0.members.contains(anchor) }
                    ?? rows.count
            }
            rows.insert(folderRow(node, parent: folder.parentID), at: insertion)
            if let parent = folder.parentID { insides[parent] = rows } else { top = rows }
        }
        return top
    }
    func rows(expanding: (UUID) -> Bool) -> [SidebarRow] {
        let insides = Dictionary(
            outline.lists.compactMap { list in list.folderID.map { ($0, list.rows) } },
            uniquingKeysWith: { first, _ in first })
        var result: [SidebarRow] = []
        func walk(_ rows: [SidebarRow]) {
            for row in rows {
                result.append(row)
                if row.kind.opensList, expanding(row.id), let inside = insides[row.id] { walk(inside) }
            }
        }
        for list in outline.lists where list.folderID == nil { walk(list.rows) }
        return result
    }
    var positions: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for row in rows(expanding: { _ in true }) {
            for id in row.kind.opensList ? [row.id] : row.members where result[id] == nil { result[id] = result.count }
        }
        return result
    }
    func stops(folders: [FolderState.Seed]) -> [SidebarRow] {
        let collapsed = Set(folders.filter(\.isCollapsed).map(\.id))
        return rows(expanding: { !collapsed.contains($0) }).filter { !$0.kind.opensList }
    }
    func step(_ id: UUID, direction: AdjacentDirection, folders: [FolderState.Seed]) -> UUID? {
        let stops = stops(folders: folders)
        guard !stops.isEmpty else { return nil }
        let shown = stops.firstIndex { $0.members.contains(id) }
        let origin: Int
        if let shown {
            origin = shown
        } else {
            let positions = positions
            let gap = positions[id].map { place in stops.filter { positions[$0.members[0]]! < place }.count } ?? 0
            origin = direction.step > 0 ? gap - 1 : gap
        }
        let reached = ((origin + direction.step) % stops.count + stops.count) % stops.count
        return reached == shown ? nil : stops[reached].members[0]
    }
    func swipe(_ id: UUID, direction: AdjacentDirection, folders: [FolderState.Seed]) -> UUID? {
        let stops = stops(folders: folders)
        if let shown = stops.firstIndex(where: { $0.members.contains(id) }) {
            let members = stops[shown].members
            let next = members.firstIndex(of: id)! + direction.step
            if members.indices.contains(next) { return members[next] }
            let reached = shown + direction.step
            guard stops.indices.contains(reached) else { return nil }
            return direction.step > 0 ? stops[reached].members.first : stops[reached].members.last
        }
        let positions = positions
        let gap = positions[id].map { place in stops.filter { positions[$0.members[0]]! < place }.count } ?? 0
        let reached = direction.step > 0 ? gap : gap - 1
        guard stops.indices.contains(reached) else { return nil }
        return direction.step > 0 ? stops[reached].members.first : stops[reached].members.last
    }
}
