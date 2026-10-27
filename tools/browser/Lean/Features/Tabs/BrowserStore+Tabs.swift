import AppKit
import WebKit

extension BrowserStore {
    @discardableResult
    func open(_ url: URL, placement: BrowserTab.Placement = .current, folderID: UUID? = nil) -> UUID {
        var tab = BrowserTab()
        tab.zoom = preferences.defaultPageZoom ?? 1
        tab.url = url
        tab.title = url.host ?? url.lastPathComponent
        tab.placement = placement
        tab.savedURL = placement == .current ? nil : url
        tab.folderID = folderID
        let index = spaceIndex(activeSpace.id)
        session.spaces[index].tabs.append(tab)
        selectTab(tab.id)
        return tab.id
    }

    func navigate(_ url: URL, in id: UUID) {
        guard let (space, tab) = tabIndex(id) else { return }
        session.spaces[space].tabs[tab].url = url
        loadPage(id)?.load(url)
        changed()
    }

    func openPopup(configuration: WKWebViewConfiguration, url: URL?, spaceID: UUID) -> WKWebView? {
        guard session.spaces.contains(where: { $0.id == spaceID }) else { return nil }
        var tab = BrowserTab()
        guard
            url.map({ ["http", "https", "file", "about", "data", "blob", "javascript"].contains($0.scheme ?? "") })
                ?? true
        else { return nil }
        tab.url = url?.scheme == "javascript" ? nil : url
        let index = spaceIndex(spaceID)
        session.spaces[index].tabs.append(tab)
        let page = BrowserPage(id: tab.id, spaceID: spaceID, configuration: configuration, owner: self)
        page.scriptMayClose = true
        pages[tab.id] = page
        runtimeRevision &+= 1
        selectTab(tab.id)
        return page.webView
    }

    func closeSelectedTab() { requestCloseSelected() }

    func deleteTab(_ id: UUID, liveFolderRefresh: Bool = false) {
        guard let (s, t) = tabIndex(id) else { return }
        let spaceID = session.spaces[s].id
        let affected = owner.contexts.values.filter {
            $0.selectedTab?.id == id || $0.windowState.tabsBySpace[spaceID] == id
        }
        detachFromSplits(id)
        let tab = session.spaces[s].tabs.remove(at: t)
        let liveFolder = session.spaces[s].folders.contains { $0.id == tab.folderID && $0.kind == .github }
        var entry = BrowserArchiveEntry(spaceID: session.spaces[s].id, tab: tab)
        entry.wasDeletedFromLiveFolder = liveFolder && !liveFolderRefresh ? true : nil
        session.archive.insert(entry, at: 0)
        unload(id)
        for context in affected {
            context.setSelectedTab(nil, in: spaceID)
            if context.activeSpace.id == spaceID { context.selectNextLoaded(excluding: id) }
        }
        if session.spaces[s].selectedTabID == id { session.spaces[s].selectedTabID = nil }
        changed()
    }

    func renameTab(_ id: UUID, to title: String) {
        guard let (s, t) = tabIndex(id) else { return }
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.spaces[s].tabs[t].customTitle = text.isEmpty ? nil : String(text.prefix(2048))
        editingTabID = nil
        changed()
    }

    func placeTab(_ id: UUID, as placement: BrowserTab.Placement, folderID: UUID? = nil) {
        guard let (s, t) = tabIndex(id), !session.spaces[s].tabs[t].isSettings else { return }
        session.spaces[s].tabs[t].placement = placement
        session.spaces[s].tabs[t].folderID = placement == .pinned ? nil : folderID
        if placement == .current {
            session.spaces[s].tabs[t].savedURL = nil
        } else if session.spaces[s].tabs[t].savedURL == nil {
            session.spaces[s].tabs[t].savedURL = session.spaces[s].tabs[t].url
        }
        changed()
    }

    func clearCurrentTabs() { requestDeleteTabs(activeSpace.tabs.filter { $0.placement == .current }.map(\.id)) }

    func requestDeleteTabs(_ ids: [UUID]) {
        Task {
            // Ask every affected document before changing any organizational state.
            guard await prepareTabs(ids) else { return }
            for id in ids { deleteTab(id) }
            selectedTabs.subtract(ids)
        }
    }

    func requestCloseSelected() {
        if let id = selectedTab?.id { requestCloseTab(id) }
    }

    func requestCloseTab(_ id: UUID) {
        guard let (space, position) = tabIndex(id) else { return }
        let tab = session.spaces[space].tabs[position]
        let originalSpace = session.spaces[space].id
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

    func adjacentTab(_ delta: Int) {
        let tabs = sidebarOrder
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == selectedTab?.id } ?? 0
        selectTab(tabs[(index + delta + tabs.count) % tabs.count].id)
    }

    func togglePin() {
        guard let tab = selectedTab else { return }
        placeTabs([tab.id], as: tab.placement == .pinned ? .current : .pinned)
    }

    func archiveSelected() {
        if let id = selectedTab?.id { requestDeleteTabs([id]) }
    }

    func placeTabs(_ ids: [UUID], as placement: BrowserTab.Placement, folderID: UUID? = nil) {
        for id in relatedTabIDs(ids) { placeTab(id, as: placement, folderID: folderID) }
    }

    func duplicateTabs(_ ids: [UUID]) {
        for id in ids {
            guard let (s, t) = tabIndex(id) else { continue }
            var tab = session.spaces[s].tabs[t]
            tab.id = UUID()
            session.spaces[s].tabs.insert(tab, at: t + 1)
            selectTab(tab.id)
        }
        changed()
    }

    func moveTabs(
        _ ids: [UUID], to destination: UUID, folderID: UUID? = nil, placement: BrowserTab.Placement? = nil,
        before: UUID? = nil
    ) {
        let ids = relatedTabIDs(ids)
        Task {
            guard await prepareTabs(ids) else { return }
            let groups = session.spaces.flatMap(\.splits).filter { Set($0.tabIDs).isSubset(of: Set(ids)) }
            guard session.spaces.contains(where: { $0.id == destination }) else { return }
            for id in ids {
                await pages[id]?.captureDocumentState()
                pages[id]?.checkpointNativeState()
            }
            for id in ids {
                guard let (s, t) = tabIndex(id), session.spaces[s].id != destination else { continue }
                let source = session.spaces[s].id
                let affected = owner.contexts.values.filter {
                    $0.selectedTab?.id == id || $0.windowState.tabsBySpace[source] == id
                }
                detachFromSplits(id)
                pages[id]?.checkpointNativeState()
                var tab = session.spaces[s].tabs.remove(at: t)
                tab.folderID = folderID
                tab.placement = placement ?? tab.placement
                if tab.placement == .current {
                    tab.savedURL = nil
                } else if tab.savedURL == nil {
                    tab.savedURL = tab.url
                }
                unload(id)
                session.spaces[spaceIndex(destination)].tabs.append(tab)
                for context in affected {
                    context.setSelectedTab(nil, in: source)
                }
            }
            if let target = session.spaces.firstIndex(where: { $0.id == destination }) {
                session.spaces[target].splits += groups.filter { group in
                    group.tabIDs.allSatisfy { id in session.spaces[target].tabs.contains { $0.id == id } }
                }
            }
            reorderSidebarItems(ids, in: destination, before: before)
            if let first = ids.first { selectTab(first) }
            changed()
        }
    }
}
