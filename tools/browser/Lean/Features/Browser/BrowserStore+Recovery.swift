import AppKit
import WebKit

extension BrowserStore {
    func setSelectedTab(_ tabID: UUID?, in spaceID: UUID) {
        windowState.tabsBySpace[spaceID] = tabID
        if tabID == nil { windowState.emptySpaces.insert(spaceID) } else { windowState.emptySpaces.remove(spaceID) }
        if let index = session.spaces.firstIndex(where: { $0.id == spaceID }) {
            session.spaces[index].selectedTabID = tabID
        }
        if let tabID {
            windowState.recentTabs.removeAll { $0 == tabID }
            windowState.recentTabs.insert(tabID, at: 0)
            if let (s, t) = tabIndex(tabID) { session.spaces[s].tabs[t].lastUsed = Date() }
        }
    }

    func unloadSafely(_ id: UUID, automatic: Bool = false) async -> Bool {
        guard let page = pages[id] else { return true }
        if automatic && (owner.visiblePageIDs.contains(id) || page.isProtectedFromUnloading) { return false }
        guard await page.prepareToClose(automatically: automatic) else { return false }
        guard !automatic || (!owner.visiblePageIDs.contains(id) && !page.isProtectedFromUnloading) else { return false }
        await page.captureDocumentState()
        page.checkpointNativeState()
        unload(id)
        changed()
        return true
    }

    func prepareTabs(_ ids: [UUID]) async -> Bool {
        let revisions = Dictionary(
            uniqueKeysWithValues: Set(ids).compactMap { id in pages[id].map { (id, $0.documentRevision) } })
        for id in ids { if let page = pages[id], !(await page.prepareToClose()) { return false } }
        return revisions.allSatisfy { pages[$0.key]?.documentRevision == $0.value }
    }

    func requestDeleteTabs(_ ids: [UUID]) {
        Task {
            // Ask every affected document before changing any organizational state.
            guard await prepareTabs(ids) else { return }
            for id in ids { deleteTab(id) }
            selectedTabs.subtract(ids)
        }
    }

    func requestCloseSelected() {
        guard let tab = selectedTab else { return }
        let originalSpace = activeSpace.id
        if tab.placement != .current, let saved = tab.savedURL, !BrowserURLs.same(tab.url, saved) {
            navigate(saved, in: tab.id)
            return
        }
        if tab.placement == .current {
            requestDeleteTabs([tab.id])
        } else {
            Task {
                guard await unloadSafely(tab.id) else { return }
                detachFromSplits(tab.id)
                let affected = owner.contexts.values.filter {
                    $0.activeSpace.id == originalSpace && $0.selectedTab?.id == tab.id
                }
                for context in affected {
                    context.selectNextLoaded(excluding: tab.id)
                }
                changed()
            }
        }
    }

    func savePrivateSpace(name: String = "Private", color: Int = 4) {
        var space = BrowserSpace()
        space.name = name
        space.color = color
        space.isPrivate = true
        session.spaces.append(space)
        selectSpace(space.id)
        _ = integration(for: space.id)
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

    func selectRecentTab(delta: Int) {
        if !recentSwitcherPresented {
            recentSwitcherIndex = 0
            recentSwitcherPresented = true
        }
        let ids = recentTabIDs
        guard !ids.isEmpty else { return }
        recentSwitcherIndex = (recentSwitcherIndex + delta + ids.count) % ids.count
    }

    func commitRecentTab() {
        let ids = recentTabIDs
        if ids.indices.contains(recentSwitcherIndex) { selectTab(ids[recentSwitcherIndex]) }
        recentSwitcherPresented = false
    }
}
