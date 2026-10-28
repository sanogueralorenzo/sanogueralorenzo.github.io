import Foundation

extension BrowserStore {
    func duplicateTab(_ id: UUID) { duplicateTabs([id], showingCopy: true) }

    func duplicateTabs(_ ids: [UUID]) { duplicateTabs(ids, showingCopy: false) }

    private func duplicateTabs(_ ids: [UUID], showingCopy: Bool) {
        let ids = Set(ids)
        guard !isClosed, !ids.isEmpty else { return }
        let spaces = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.filter { ids.contains($0.id) }.map { ($0.id, space.id) }
            })
        guard spaces.count == ids.count, canCopyTabs(in: spaces) else { return }
        let documents = pages.filter { ids.contains($0.key) }
        let revisions = documents.mapValues(\.documentRevision)
        let shown = selectedTab?.id
        func isCurrent() -> Bool {
            !isClosed && (!showingCopy || selectedTab?.id == shown)
                && ids.allSatisfy { id in
                    guard let (s, _) = tabIndex(id), session.spaces[s].id == spaces[id] else { return false }
                    if let page = documents[id] {
                        return pages[id] === page && page.documentRevision == revisions[id]
                    }
                    return pages[id] == nil
                }
        }
        func insert() {
            guard isCurrent(), canCopyTabs(in: spaces) else { return }
            for page in documents.values { page.checkpointNativeState() }
            insertTabCopies(ids, showingCopy: showingCopy)
        }
        guard documents.values.contains(where: { $0.webView.url != nil }) else {
            insert()
            return
        }
        Task {
            for page in documents.values {
                guard isCurrent() else { return }
                await page.captureDocumentState()
            }
            insert()
        }
    }

    private func canCopyTabs(in spaces: [UUID: UUID]) -> Bool {
        Dictionary(grouping: spaces.values, by: { $0 }).allSatisfy {
            canChangeTabCount(by: $0.value.count, in: $0.key)
        }
    }

    private func insertTabCopies(_ ids: Set<UUID>, showingCopy: Bool) {
        var spaces = session.spaces
        var shownCopy: UUID?
        for index in spaces.indices {
            let source = spaces[index]
            let originals = Dictionary(uniqueKeysWithValues: source.tabs.map { ($0.id, $0) })
            let copies = source.sidebarItemIDs.compactMap { id -> (UUID, BrowserTab)? in
                guard ids.contains(id), var tab = originals[id] else { return nil }
                tab.id = UUID()
                tab.placement = .current
                tab.folderID = nil
                tab.savedURL = nil
                tab.lastUsed = Date()
                return (id, tab)
            }
            guard !copies.isEmpty else { continue }
            let copiedIDs = copies.map { $0.1.id }
            var order = source.orderedSidebarIDs
            let firstCurrent = source.sidebarEntries(parentID: nil, placement: .current).first?.id
            let destination =
                showingCopy ? firstCurrent.flatMap { order.firstIndex(of: $0) } ?? order.count : order.count
            order.insert(contentsOf: copiedIDs, at: destination)
            spaces[index].tabs.append(contentsOf: copies.map { $0.1 })
            spaces[index].sidebarOrderIDs = order
            if showingCopy {
                shownCopy = copiedIDs.first
            } else {
                let mapping = Dictionary(uniqueKeysWithValues: copies.map { ($0.0, $0.1.id) })
                for group in source.splits {
                    let members = group.tabIDs.enumerated().filter { mapping[$0.element] != nil }
                    guard members.count >= 2 else { continue }
                    var copy = BrowserSplit(tabIDs: members.compactMap { mapping[$0.element] })
                    copy.direction = group.direction
                    let fractions = members.map { group.fractions[$0.offset] }
                    let total = fractions.reduce(0, +)
                    copy.fractions = fractions.map { $0 / total }
                    spaces[index].splits.append(copy)
                }
            }
        }
        session.spaces = spaces
        if let shownCopy { selectTab(shownCopy) }
        changed()
    }
}
