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
        guard source != destination, let (s, a) = tabIndex(source), let (other, b) = tabIndex(destination),
            s == other, !session.spaces[s].tabs[a].isSettings, !session.spaces[s].tabs[b].isSettings
        else { return }
        let existing = session.spaces[s].splits.first { $0.tabIDs.contains(source) }
        guard (existing?.tabIDs.count ?? 1) < 4 else { return }
        detachFromSplits(destination)
        if let existing, let index = session.spaces[s].splits.firstIndex(where: { $0.id == existing.id }) {
            session.spaces[s].splits[index].tabIDs.append(destination)
            let count = session.spaces[s].splits[index].tabIDs.count
            session.spaces[s].splits[index].fractions = Array(repeating: 1 / Double(count), count: count)
        } else {
            session.spaces[s].splits.append(BrowserSplit(tabIDs: [source, destination]))
        }
        let placement = session.spaces[s].tabs[a].placement
        let folder = session.spaces[s].tabs[a].folderID
        placeTabs([source, destination], as: placement, folderID: folder)
        selectTab(destination)
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
        session.spaces[spaceIndex(activeSpace.id)].splits.removeAll { $0.id == split.id }
        changed()
    }

    func detachFromSplits(_ id: UUID) {
        for index in session.spaces.indices {
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
        var result = Set(ids)
        for split in session.spaces.flatMap(\.splits) where !result.isDisjoint(with: split.tabIDs) {
            result.formUnion(split.tabIDs)
        }
        return session.spaces.flatMap(\.tabs).filter { result.contains($0.id) }.map(\.id)
    }
}
