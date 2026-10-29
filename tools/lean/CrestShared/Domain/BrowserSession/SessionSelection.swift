import Foundation

struct SessionSelection {
    struct Root {
        let id: UUID
        let kind: SidebarRowKind
        var isFolder: Bool { kind.opensList }
    }
    let roots: [Root]
    let folders: Set<UUID>
    let members: [TabState.Seed]
    var memberIDs: [UUID] { members.map(\.id) }
    var holdsFolders: Bool { !folders.isEmpty }
    func holds(_ id: UUID) -> Bool { members.contains { $0.id == id } }
}

extension SessionTabs {
    func select(_ requested: TabSelection) throws -> SessionSelection {
        let picked = requested.tabIDs + requested.folderIDs
        guard !picked.isEmpty, Set(picked).count == picked.count,
            requested.folderIDs.allSatisfy({ id in folders.contains { $0.id == id } }),
            requested.tabIDs.allSatisfy({ id in tabs.contains { $0.id == id } })
        else { throw Rejection.selectionChanged(SelectionChanged()) }
        let selected = try resolve(tabIDs: requested.tabIDs, folderIDs: requested.folderIDs)
        let seen = Set(requested.memberTabIDs)
        guard !selected.members.contains(where: Self.isStartPage), seen.count == requested.memberTabIDs.count,
            selected.members.count == seen.count, selected.members.allSatisfy({ seen.contains($0.id) })
        else {
            throw Rejection.selectionChanged(SelectionChanged())
        }
        return selected
    }
    func preview(tabIDs: [UUID], folderIDs: [UUID]) throws -> SessionSelection {
        var seen: Set<UUID> = []
        let requestedTabs = tabIDs.filter { id in
            seen.insert(id).inserted && tabs.contains { $0.id == id && !Self.isStartPage($0) }
        }
        seen.removeAll()
        let requestedFolders = folderIDs.filter { id in seen.insert(id).inserted && folders.contains { $0.id == id } }
        let selected = try resolve(tabIDs: requestedTabs, folderIDs: requestedFolders)
        return SessionSelection(
            roots: selected.roots, folders: selected.folders, members: selected.members.filter { !Self.isStartPage($0) }
        )
    }
    private func resolve(tabIDs: [UUID], folderIDs: [UUID]) throws -> SessionSelection {
        let tree = SessionFolders(folders)
        let subtrees = try Dictionary(uniqueKeysWithValues: folderIDs.map { ($0, try tree.subtree($0)) })
        let covered = Set(subtrees.flatMap { id, held in held.filter { $0 != id } })
        let held = Set(subtrees.values.flatMap { $0 })
        let positions = SessionSidebar(tabs: tabs, folders: folders).positions
        var roots = folderIDs.filter { !covered.contains($0) }.map { SessionSelection.Root(id: $0, kind: .folder) }
        roots += try tabIDs.filter { try tab($0).folderID.map { !held.contains($0) } ?? true }.map {
            SessionSelection.Root(id: $0, kind: .tab)
        }
        roots.sort { positions[$0.id, default: Int.max] < positions[$1.id, default: Int.max] }
        let members = try roots.flatMap { root in
            root.isFolder
                ? tabs.filter { $0.folderID.map { subtrees[root.id]!.contains($0) } == true } : [try tab(root.id)]
        }
        return SessionSelection(roots: roots, folders: held, members: members)
    }
    func requireWholeSplits(_ selection: SessionSelection) throws {
        for value in selection.members {
            if let group = value.splitGroupID, try splitMembers(value.id).contains(where: { !selection.holds($0.id) }) {
                throw Rejection.incompleteSplit(IncompleteSplit(groupID: group))
            }
        }
    }
    func requireSelectedTabs(_ selection: SessionSelection) throws {
        try requireWholeSplits(selection)
        guard !selection.holdsFolders else { throw Rejection.selectionHoldsFolders(SelectionHoldsFolders()) }
    }
    private func groups(_ selection: SessionSelection) -> [UUID] {
        var seen: Set<UUID> = []
        return selection.members.compactMap(\.splitGroupID).filter { seen.insert($0).inserted }
    }
    mutating func close(_ selection: SessionSelection, shown: UUID?, fallback: UUID?, at now: Date) throws -> UUID? {
        try requireSelectedTabs(selection)
        if let durable = selection.members.first(where: { $0.placement.isDurable }) {
            throw Rejection.currentTabsOnly(CurrentTabsOnly(tabID: durable.id))
        }
        return try dismiss(
            selection.memberIDs, selected: shown, fallback: fallback, at: now, deleting: false, ensuresSelection: false,
            resetsPlacement: false)
    }
    mutating func delete(_ selection: SessionSelection, shown: UUID?, fallback: UUID?, at now: Date) throws -> UUID? {
        try requireSelectedTabs(selection)
        let next = try dismiss(
            selection.memberIDs, selected: shown, fallback: fallback, at: now, deleting: true, ensuresSelection: true,
            resetsPlacement: true)
        return shown.map(selection.holds) == true ? tabs.contains(where: { $0.id == fallback }) ? fallback : nil : next
    }
    mutating func duplicate(_ selection: SessionSelection, ids: () -> UUID, at now: Date) throws -> [Copy] {
        try requireSelectedTabs(selection)
        var copies: [Copy] = []
        for source in selection.members {
            let value = try duplicate(source.id, ids: ids, at: now, index: tabs.count)
            copies.append(Copy(source: source.id, copy: value.id))
        }
        for group in groups(selection) {
            let copied = selection.members.filter { $0.splitGroupID == group }.map { value in
                copies.first { $0.source == value.id }!.copy
            }
            guard copied.count >= 2 else { continue }
            let newGroup = ids()
            for id in copied.dropFirst() { try joinInPlace(id, to: copied[0], index: nil, group: newGroup, at: now) }
        }
        return copies
    }
    mutating func split(
        _ selection: SessionSelection, target: UUID?, index: Int?, shown: UUID?, ids: () -> UUID, at now: Date
    ) throws -> (shown: UUID?, copies: [Copy]) {
        try requireSelectedTabs(selection)
        var target = target ?? selection.memberIDs[0]
        if Self.isStartPage(try tab(target)) { throw Rejection.webPagesOnly(WebPagesOnly(tabID: target)) }
        let existing = Set(try splitMembers(target).map(\.id))
        let count = existing.union(selection.memberIDs).count
        guard count >= 2 else { throw Rejection.splitNeedsTwoTabs(SplitNeedsTwoTabs(limit: Self.maximumSplitMembers)) }
        guard count <= Self.maximumSplitMembers else {
            throw Rejection.splitLimitReached(SplitLimitReached(limit: Self.maximumSplitMembers))
        }
        var shown = shown
        var copies: [Copy] = []
        var insertion = index
        for id in selection.memberIDs where !existing.contains(id) {
            let joined = try join(id, to: target, index: insertion, ids: ids, at: now)
            copies += joined.copies
            shown = joined.selected
            if let copy = joined.copies.first(where: { $0.source == target }) { target = copy.copy }
            if let value = insertion { insertion = value + 1 }
        }
        return (shown, copies)
    }
    mutating func separate(_ selection: SessionSelection, at now: Date) throws {
        try requireSelectedTabs(selection)
        for group in groups(selection) { dissolveSplit(group, at: now) }
    }
    mutating func move(
        _ selection: SessionSelection, to destination: inout SessionTabs, shown: UUID?, fallback: UUID?,
        destinationShown: UUID?, follows: Bool, at now: Date
    ) throws -> (shown: UUID?, destinationShown: UUID?) {
        try requireSelectedTabs(selection)
        if let member = selection.members.first(where: { $0.splitGroupID != nil }) {
            throw Rejection.cannotMoveSplitAcrossSpaces(CannotMoveSplitAcrossSpaces(tabID: member.id))
        }
        for placement in TabPlacement.all {
            try Self.requireRoom(
                placement,
                count: destination.tabs.filter { $0.placement == placement }.count
                    + selection.members.filter { $0.placement == placement }.count)
        }
        let followed = shown.flatMap { selection.holds($0) ? $0 : nil } ?? selection.memberIDs[0]
        var shown = shown
        for id in selection.memberIDs {
            shown = try transfer(
                id, to: &destination, selected: shown, fallback: fallback, placement: nil, folder: nil, before: nil,
                afterSelection: false, destinationSelection: destinationShown, at: now)
        }
        guard follows else { return (shown, destinationShown) }
        try destination.edit(followed) { $0.lastActivatedAt = now }
        return (shown, followed)
    }
    mutating func order(_ requested: [UUID]) throws {
        let members = try requested.map(tab)
        let held = Set(requested)
        let insertion = tabs.firstIndex { held.contains($0.id) }!
        tabs.removeAll { held.contains($0.id) }
        tabs.insert(contentsOf: members, at: insertion)
    }
    func splitRuns(_ requested: [UUID], leavesSplits: Bool) throws -> [UUID] {
        guard !leavesSplits else { return requested }
        var seen: Set<UUID> = []
        return try requested.flatMap { try splitMembers($0).map(\.id) }.filter { seen.insert($0).inserted }
    }
}
