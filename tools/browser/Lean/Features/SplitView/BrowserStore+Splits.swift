import Foundation

extension BrowserStore {
    var activeSplit: BrowserSplit? {
        guard let id = selectedTab?.id else { return nil }
        return activeSpace.splits.first { $0.tabIDs.contains(id) }
    }

    var visiblePages: [BrowserPage] {
        _ = runtimeRevision
        guard let id = selectedTab?.id else { return [] }
        return (activeSplit?.tabIDs ?? [id]).compactMap { pages[$0] }
    }

    func beginSplit(with id: UUID? = nil) {
        guard let source = id ?? selectedTab?.id,
            let (space, index) = tabIndex(source), !session.spaces[space].tabs[index].isSettings
        else { return }
        presentAddress(newTab: true)
        pendingSplitSourceID = source
    }

    func split(_ source: UUID, with destination: UUID) {
        joinTabs([destination], to: source)
    }

    func combineTabs(_ ids: [UUID]) {
        let requested = Set(ids)
        let ordered = activeSpace.sidebarItemIDs.filter(requested.contains)
        guard ordered.count == requested.count, let target = ordered.first else { return }
        joinTabs(ordered, to: target)
    }

    func canDropSidebarTabsIntoSplit(_ payload: BrowserDragPayload) -> Bool {
        guard !isClosed, !addressPresented, payload.kind == .tabs, payload.folderIDs.isEmpty,
            payload.spaceID == activeSpace.id, !payload.ids.isEmpty,
            let target = selectedTab, !target.isSettings, target.url != nil
        else { return false }
        let ids = Set(payload.ids)
        let tabs = activeSpace.tabs.filter { ids.contains($0.id) }
        guard tabs.count == ids.count, tabs.allSatisfy({ !$0.isSettings && $0.url != nil }) else { return false }
        let members = Set(activeSplit?.tabIDs ?? [target.id])
        guard activeSpace.tabs.filter({ members.contains($0.id) }).allSatisfy({ !$0.isSettings && $0.url != nil })
        else { return false }
        return (2...4).contains(members.union(ids).count)
    }

    @discardableResult
    func dropSidebarTabsIntoSplit(_ payload: BrowserDragPayload, at index: Int) -> Bool {
        guard canDropSidebarTabsIntoSplit(payload), let target = selectedTab?.id else { return false }
        return joinTabs(payload.ids, to: target, dropIndex: index, moves: true)
    }

    @discardableResult
    private func joinTabs(_ ids: [UUID], to target: UUID, dropIndex: Int? = nil, moves: Bool = false) -> Bool {
        guard !isClosed, let (s, _) = tabIndex(target) else { return false }
        let source = session.spaces[s]
        guard let edit = source.joiningTabs(ids, to: target, dropIndex: dropIndex, moves: moves),
            canChangeTabCount(by: edit.copies.count, in: source.id)
        else { return false }
        let affected = Set(ids).union(source.splits.first { $0.tabIDs.contains(target) }?.tabIDs ?? [target])
        let groups = source.splits.filter { !Set($0.tabIDs).isDisjoint(with: affected) }
        let originals = Dictionary(uniqueKeysWithValues: source.tabs.map { ($0.id, $0) })
        let shown = selectedTab?.id
        let spaceID = activeSpace.id
        let commit: @MainActor () -> Bool = { [self] in
            guard !isClosed, activeSpace.id == spaceID, selectedTab?.id == shown,
                let index = session.spaces.firstIndex(where: { $0.id == source.id })
            else { return false }
            let current = session.spaces[index]
            guard current.splits.filter({ !Set($0.tabIDs).isDisjoint(with: affected) }) == groups,
                affected.allSatisfy({ id in
                    current.tabs.contains {
                        $0.id == id && $0.placement == originals[id]?.placement
                            && $0.folderID == originals[id]?.folderID
                    }
                }),
                let edit = current.joiningTabs(ids, to: target, dropIndex: dropIndex, moves: moves),
                canChangeTabCount(by: edit.copies.count, in: source.id)
            else { return false }
            var candidate = session
            candidate.spaces[index] = edit.space
            guard (try? candidate.validate()) != nil else { return false }
            session = candidate
            selectTab(edit.shown)
            changed()
            return true
        }
        if edit.copies.isEmpty { return commit() }
        withCurrentTabState(affected) { _ = commit() }
        return true
    }

    func changeSplitDirection() {
        guard let split = activeSplit else { return }
        let s = spaceIndex(activeSpace.id)
        guard let index = session.spaces[s].splits.firstIndex(where: { $0.id == split.id }) else { return }
        session.spaces[s].splits[index].direction = split.direction == .horizontal ? .vertical : .horizontal
        changed()
    }

    func leaveSplit() {
        guard let split = activeSplit else { return }
        for page in visiblePages where page.id != selectedTab?.id { page.lastSelected = Date() }
        session.spaces[spaceIndex(activeSpace.id)].sidebarOrderIDs = activeSpace.orderedSidebarIDs
        session.spaces[spaceIndex(activeSpace.id)].splits.removeAll { $0.id == split.id }
        changed()
    }

    func detachFromSplits(_ id: UUID) {
        for index in session.spaces.indices {
            if session.spaces[index].splits.contains(where: { $0.tabIDs.contains(id) }) {
                session.spaces[index].sidebarOrderIDs = session.spaces[index].orderedSidebarIDs
            }
            for split in session.spaces[index].splits.indices {
                guard let removed = session.spaces[index].splits[split].tabIDs.firstIndex(of: id) else { continue }
                session.spaces[index].splits[split].tabIDs.remove(at: removed)
                session.spaces[index].splits[split].fractions.remove(at: removed)
                let total = session.spaces[index].splits[split].fractions.reduce(0, +)
                if total > 0 {
                    session.spaces[index].splits[split].fractions = session.spaces[index].splits[split].fractions.map {
                        $0 / total
                    }
                }
            }
            session.spaces[index].splits.removeAll { $0.tabIDs.count < 2 }
        }
    }

    func focusSplit(_ delta: Int) {
        guard let split = activeSplit, let index = split.tabIDs.firstIndex(of: selectedTab?.id ?? UUID()) else {
            return
        }
        selectTab(split.tabIDs[(index + delta + split.tabIDs.count) % split.tabIDs.count])
    }

    func moveSplitCard(_ delta: Int) {
        guard let split = activeSplit, let index = split.tabIDs.firstIndex(of: selectedTab?.id ?? UUID()),
            let position = activeSpace.splits.firstIndex(where: { $0.id == split.id }),
            split.tabIDs.indices.contains(index + delta)
        else { return }
        let s = spaceIndex(activeSpace.id)
        session.spaces[s].sidebarOrderIDs = activeSpace.orderedSidebarIDs
        session.spaces[s].splits[position].tabIDs.swapAt(index, index + delta)
        session.spaces[s].splits[position].fractions.swapAt(index, index + delta)
        changed()
    }

    func resizeSplit(_ id: UUID, fractions: [Double]) {
        let s = spaceIndex(activeSpace.id)
        guard let i = session.spaces[s].splits.firstIndex(where: { $0.id == id }),
            fractions.count == session.spaces[s].splits[i].tabIDs.count,
            fractions.allSatisfy({ $0.isFinite && $0 > 0 })
        else { return }
        let total = fractions.reduce(0, +)
        session.spaces[s].splits[i].fractions = fractions.map { $0 / total }
        changed()
    }

    func relatedTabIDs(_ ids: [UUID]) -> [UUID] {
        let available = Set(session.spaces.flatMap { $0.tabs.map(\.id) })
        let groups = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap(\.splits).flatMap { split in
                split.tabIDs.map { ($0, split.tabIDs) }
            })
        var seen = Set<UUID>()
        return ids.flatMap { groups[$0] ?? [$0] }.filter { available.contains($0) && seen.insert($0).inserted }
    }
}

extension BrowserSpace {
    fileprivate func joiningTabs(_ ids: [UUID], to targetID: UUID, dropIndex: Int? = nil, moves: Bool = false) -> (
        space: BrowserSpace, shown: UUID, copies: Set<UUID>
    )? {
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        guard let target = byID[targetID], !target.isSettings, ids.allSatisfy({ byID[$0]?.isSettings == false }) else {
            return nil
        }
        let existing = splits.first { $0.tabIDs.contains(targetID) }
        let targetIDs = existing?.tabIDs ?? [targetID]
        var seen = Set(targetIDs)
        let joining = ids.filter { seen.insert($0).inserted }
        guard !joining.isEmpty || moves, targetIDs.count + joining.count <= 4 else { return nil }
        let copyTarget = !moves && target.placement != .current
        var copied = Set<UUID>()
        let projection = BrowserSplitDropLayout(
            ids: targetIDs, incoming: ids,
            fractions: existing?.fractions ?? [1], insertionIndex: dropIndex ?? targetIDs.count)
        let ordered = moves ? projection.orderedIDs : targetIDs + joining
        let members = ordered.compactMap { id -> BrowserTab? in
            guard var tab = byID[id], !tab.isSettings else { return nil }
            if targetIDs.contains(id) ? copyTarget : (!moves && tab.placement != .current) {
                copied.insert(id)
                tab = tab.currentCopy()
            }
            tab.placement = .current
            tab.folderID = target.placement != .current ? nil : target.folderID
            tab.savedURL = nil
            return tab
        }
        guard members.count == targetIDs.count + joining.count, let shown = (moves ? ids.last : members.last?.id) else {
            return nil
        }
        let moving = Set(members.map(\.id))
        let order = orderedSidebarIDs
        var remaining = order.filter { !moving.contains($0) }
        let destination: Int
        if target.placement != .current {
            let first = sidebarEntries(parentID: nil, placement: .current).first { !moving.contains($0.id) }?.id
            destination = first.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
        } else {
            let start = order.firstIndex(of: targetIDs[0]) ?? order.count
            destination = order.prefix(start).filter { !moving.contains($0) }.count
        }
        remaining.insert(contentsOf: members.map(\.id), at: destination)
        var result = self
        result.sidebarOrderIDs = remaining
        result.tabs.removeAll { moving.contains($0.id) }
        result.tabs.append(contentsOf: members)
        result.splits = splits.compactMap { group in
            if !copyTarget && group.id == existing?.id { return nil }
            let kept = group.tabIDs.indices.filter { !moving.contains(group.tabIDs[$0]) }
            guard kept.count >= 2 else { return nil }
            if kept.count == group.tabIDs.count { return group }
            var group = group
            group.tabIDs = kept.map { group.tabIDs[$0] }
            let fractions = kept.map { group.fractions[$0] }
            let total = fractions.reduce(0, +)
            group.fractions = fractions.map { $0 / total }
            return group
        }
        var group = BrowserSplit(tabIDs: members.map(\.id))
        if let existing {
            if !copyTarget { group.id = existing.id }
            group.direction = existing.direction
        }
        if moves { group.fractions = projection.projectedFractions }
        result.splits.append(group)
        return (result, shown, copied)
    }
}
