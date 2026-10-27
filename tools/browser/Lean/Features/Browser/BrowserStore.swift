import AppKit
import Foundation
import Observation
import WebKit

/// A window's selection and presentation over the shared Swift session owner.
@MainActor
@Observable
final class BrowserStore {
    // MARK: - Variables

    let owner: BrowserSessionOwner
    let id: UUID
    var isClosed = false
    @ObservationIgnored weak var window: NSWindow?
    var selectedTabs: Set<UUID> = []
    var selectedFolders: Set<UUID> = []
    var selectionAnchor: UUID?
    var selectionFocusedID: UUID?
    var selectionRangeBase: Set<UUID>?
    var sidebarKeyboardSelection = false
    var isDragging = false
    var recentSwitcherPresented = false
    var recentSwitcherIndex = 0
    var session: BrowserSession {
        get { owner.session }
        set { owner.session = newValue }
    }
    var windowState: BrowserWindowState {
        get { session.windows.first { $0.id == id } ?? BrowserWindowState(id: id, spaceID: session.spaces[0].id) }
        set {
            if let i = owner.session.windows.firstIndex(where: { $0.id == id }) { owner.session.windows[i] = newValue }
        }
    }
    var addressPresented = false
    var addressPresentationID = UUID()
    var addressCreatesTab = false
    var addressText = ""
    var utility: BrowserUtility?
    var findsPage = false
    var findText = ""
    var siteSettingsPresented = false
    var importPresented = false
    var exportPresented = false
    var notice: String?
    var settingsTabs: [UUID: BrowserSettingsTabState] = [:]
    var settingsState: BrowserSettingsTabState {
        get { selectedTab.flatMap { settingsTabs[$0.id] } ?? BrowserSettingsTabState() }
        set { if let id = selectedTab?.id { settingsTabs[id] = newValue } }
    }
    var settingsSelection: BrowserSettingsSelection {
        get { settingsState.selection }
        set { settingsState.selection = newValue }
    }
    var settingsSpacePrivacy: Bool {
        get { settingsState.spacePrivacy }
        set { settingsState.spacePrivacy = newValue }
    }
    var isFullScreen = false
    var sidebarRevealed = false
    var sidebarEditorPresented = false
    var sidebarMenuPresented = false
    var isResizingSidebar = false
    var sidebarWidth: CGFloat {
        SidebarGeometry.clampedWidth(CGFloat(preferences.sidebarWidth ?? Double(SidebarGeometry.width)))
    }
    var pendingSplitSourceID: UUID?
    var editingTabID: UUID?
    var editingFolderID: UUID?
    var runtimeRevision: Int {
        get { owner.runtimeRevision }
        set { owner.runtimeRevision = newValue }
    }
    var pages: [UUID: BrowserPage] {
        get { owner.pages }
        set { owner.pages = newValue }
    }
    var profiles: [UUID: WKWebsiteDataStore] {
        get { owner.profiles }
        set { owner.profiles = newValue }
    }
    var integrations: [UUID: GitHubFolder] {
        get { owner.integrations }
        set { owner.integrations = newValue }
    }
    var downloads: [ObjectIdentifier: BrowserDownload] {
        get { owner.downloads }
        set { owner.downloads = newValue }
    }
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    var activeSpace: BrowserSpace {
        session.spaces.first { $0.id == windowState.spaceID } ?? session.spaces[0]
    }
    var selectedTab: BrowserTab? {
        if windowState.emptySpaces.contains(activeSpace.id) { return nil }
        let selected = windowState.tabsBySpace[activeSpace.id] ?? activeSpace.selectedTabID
        return activeSpace.tabs.first { $0.id == selected }
    }
    var activePage: BrowserPage? {
        _ = runtimeRevision
        return selectedTab.flatMap { pages[$0.id] }
    }
    var playingPage: BrowserPage? {
        _ = runtimeRevision
        let visible = pages.values.filter { page in
            !page.nowPlayingHidden && session.spaces.first(where: { $0.id == page.spaceID })?.isPrivate == false
        }
        return visible.filter { $0.isPlaying }.max { $0.lastSelected < $1.lastSelected }
            ?? owner.media?.currentPage.flatMap { page in visible.contains(where: { $0.id == page.id }) ? page : nil }
    }
    var preferences: BrowserPreferences { session.preferences }
    var activeDownloads: [BrowserDownload] {
        _ = runtimeRevision
        return Array(downloads.values)
    }
    var showsSidebar: Bool {
        sidebarRevealed || sidebarEditorPresented || sidebarMenuPresented || isResizingSidebar
            || editingTabID != nil || editingFolderID != nil || utility != nil || activeSpace.tabs.isEmpty
    }

    // MARK: - Initializers

    init(owner: BrowserSessionOwner, id: UUID) {
        self.owner = owner
        self.id = id
        loadSelection()
        for space in session.spaces { _ = integration(for: space.id) }
    }

    // MARK: - Actions - Navigation

    func presentAddress(newTab: Bool = false) {
        addressPresentationID = UUID()
        sidebarRevealed = false
        pendingSplitSourceID = nil
        utility = nil
        addressCreatesTab = newTab || selectedTab == nil || selectedTab?.isSettings == true
        addressText = addressCreatesTab ? "" : selectedTab?.url?.absoluteString ?? ""
        addressPresented = true
    }

    func submitAddress(_ text: String) {
        guard let url = preferences.searchProvider.resolve(text) else { return }
        addressPresented = false
        if addressCreatesTab || selectedTab == nil {
            let source = pendingSplitSourceID
            let id = open(url)
            pendingSplitSourceID = nil
            if let source { split(source, with: id) }
        } else if let id = selectedTab?.id {
            navigate(url, in: id)
        }
    }

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

    func selectTab(_ id: UUID, keepingSelection: Bool = false) {
        if !keepingSelection {
            selectedTabs = [id]
            selectedFolders = []
            selectionAnchor = nil
            sidebarKeyboardSelection = false
        }
        guard let (space, _) = tabIndex(id) else { return }
        let previousPages = visiblePages
        windowState.spaceID = session.spaces[space].id
        if !session.spaces[space].isPrivate { session.selectedSpaceID = session.spaces[space].id }
        setSelectedTab(id, in: session.spaces[space].id)
        utility = nil
        findsPage = false
        loadSelection()
        let visible = owner.visiblePageIDs
        for page in previousPages where !visible.contains(page.id) {
            page.lastSelected = Date()
            page.beginPictureInPicture()
        }
        changed()
    }

    func selectSpace(_ id: UUID) {
        guard session.spaces.contains(where: { $0.id == id }), id != activeSpace.id else { return }
        let previous = visiblePages
        windowState.spaceID = id
        if !activeSpace.isPrivate { session.selectedSpaceID = id }
        selectedTabs.removeAll()
        selectedFolders.removeAll()
        selectionAnchor = nil
        selectionRangeBase = nil
        sidebarKeyboardSelection = false
        utility = nil
        findsPage = false
        loadSelection()
        for page in previous where !owner.visiblePageIDs.contains(page.id) {
            page.lastSelected = Date()
            page.beginPictureInPicture()
        }
        changed()
    }

    func openSettings() {
        if let tab = activeSpace.tabs.first(where: \.isSettings) {
            selectTab(tab.id)
            return
        }
        var tab = BrowserTab()
        tab.title = "Settings"
        tab.isSettings = true
        let index = spaceIndex(activeSpace.id)
        session.spaces[index].tabs.append(tab)
        selectTab(tab.id)
    }

    private func loadSelection() {
        guard let id = selectedTab?.id else { return }
        for tabID in activeSplit?.tabIDs ?? [id] {
            guard let page = loadPage(tabID) else { continue }
            page.lastSelected = Date()
            page.pictureInPicture?.returnToTab()
            if owner.activeWindowID == self.id || window?.isKeyWindow == true {
                page.owner = self
                page.hostingWindowID = self.id
            }
        }
        runtimeRevision &+= 1
    }

    @discardableResult
    func loadPage(_ id: UUID) -> BrowserPage? {
        if let page = pages[id] { return page }
        guard let (s, t) = tabIndex(id) else { return nil }
        let tab = session.spaces[s].tabs[t]
        guard !tab.isSettings, tab.url != nil else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile(for: session.spaces[s].id)
        let page = BrowserPage(id: id, spaceID: session.spaces[s].id, configuration: configuration, owner: self)
        page.hostingWindowID = self.id
        pages[id] = page
        runtimeRevision &+= 1
        page.restore(tab)
        return page
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

    // MARK: - Actions - Tabs

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

    func selectNextLoaded(excluding id: UUID) {
        let tabs = activeSpace.tabs
        let ordered =
            tabs.filter { $0.placement == .pinned } + tabs.filter { $0.placement == .saved }
            + tabs.filter { $0.placement == .current }
        let next = ordered.first { $0.id != id && (pages[$0.id] != nil || $0.isSettings) }
        setSelectedTab(next?.id, in: activeSpace.id)
        runtimeRevision &+= 1
    }

    func isLoaded(_ tab: BrowserTab) -> Bool {
        _ = runtimeRevision
        return pages[tab.id] != nil || tab.isSettings
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

    func restore(_ entry: BrowserArchiveEntry) {
        let spaceID = session.spaces.contains(where: { $0.id == entry.spaceID }) ? entry.spaceID : activeSpace.id
        var tab = entry.tab
        tab.id = UUID()
        tab.folderID = nil
        session.spaces[spaceIndex(spaceID)].tabs.append(tab)
        session.archive.removeAll { $0.id == entry.id }
        selectTab(tab.id)
    }

    // MARK: - Actions - Spaces and folders

    func saveSpace(id: UUID?, name: String, color: Int, isPrivate: Bool = false) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, let index = session.spaces.firstIndex(where: { $0.id == id }) {
            session.spaces[index].name = title.isEmpty ? "Space" : String(title.prefix(256))
            session.spaces[index].color = color
        } else {
            var space = BrowserSpace()
            space.name = title.isEmpty ? "Space" : String(title.prefix(256))
            space.color = color
            space.isPrivate = isPrivate
            session.spaces.append(space)
            selectSpace(space.id)
            _ = integration(for: space.id)
        }
        changed()
    }

    func deleteSpace(_ id: UUID, prepared: Bool = false) {
        guard let space = session.spaces.first(where: { $0.id == id }),
            space.isPrivate || session.spaces.filter({ !$0.isPrivate }).count > 1
        else { return }
        Task {
            if !prepared {
                guard await prepareTabs(space.tabs.map(\.id)), await prepareToDeleteSpace(id) else { return }
            }
            guard let current = session.spaces.first(where: { $0.id == id }),
                Set(current.tabs.map(\.id)) == Set(space.tabs.map(\.id))
            else { return }
            for tab in space.tabs { unload(tab.id) }
            integrations.removeValue(forKey: id)?.invalidate()
            profiles[id] = nil
            session.spaces.removeAll { $0.id == id }
            session.history.removeAll { $0.spaceID == id }
            session.archive.removeAll { $0.spaceID == id }
            if !session.spaces.contains(where: { !$0.isPrivate }) { session.spaces.append(BrowserSpace()) }
            let fallback = session.spaces.first(where: { !$0.isPrivate })!.id
            for context in owner.contexts.values where context.windowState.spaceID == id {
                context.windowState.spaceID = fallback
                context.resumePages()
            }
            for i in session.windows.indices {
                session.windows[i].tabsBySpace[id] = nil
                session.windows[i].emptySpaces.remove(id)
                if session.windows[i].spaceID == id { session.windows[i].spaceID = fallback }
            }
            if session.selectedSpaceID == id { session.selectedSpaceID = fallback }
            if !space.isPrivate { WKWebsiteDataStore.remove(forIdentifier: id) { _ in } }
            changed()
        }
    }

    @discardableResult
    func addFolder(parentID: UUID? = nil, github: Bool = false, in spaceID: UUID? = nil) -> UUID {
        let index = spaceIndex(spaceID ?? activeSpace.id)
        var folder = BrowserFolder()
        folder.parentID = parentID
        folder.placement = parentID.flatMap { id in session.spaces[index].folders.first { $0.id == id }?.placement }
        if github {
            if let existing = session.spaces[index].folders.first(where: { $0.kind == .github }) { return existing.id }
            folder.kind = .github
            folder.title = "GitHub"
            session.spaces[index].githubDismissed = false
        }
        session.spaces[index].folders.append(folder)
        if !github { editingFolderID = folder.id }
        changed()
        return folder.id
    }

    func updateFolder(_ id: UUID, change: (inout BrowserFolder) -> Void) {
        let index = spaceIndex(activeSpace.id)
        guard let position = session.spaces[index].folders.firstIndex(where: { $0.id == id }) else { return }
        change(&session.spaces[index].folders[position])
        session.spaces[index].folders[position].title = String(
            session.spaces[index].folders[position].title.prefix(256))
        changed()
    }

    func deleteFolder(_ id: UUID) {
        let space = activeSpace
        let ids = descendants(id, in: space)
        let tabs = space.tabs.filter { $0.folderID.map { ids.contains($0) } ?? false }.map(\.id)
        Task {
            guard await prepareTabs(tabs) else { return }
            guard let index = session.spaces.firstIndex(where: { $0.id == space.id }) else { return }
            for id in tabs { deleteTab(id) }
            if space.folders.contains(where: { ids.contains($0.id) && $0.kind == .github }) {
                session.spaces[index].githubDismissed = true
            }
            session.spaces[index].folders.removeAll { ids.contains($0.id) }
            changed()
        }
    }

    // MARK: - Actions - Pages and profile services

    func profile(for spaceID: UUID) -> WKWebsiteDataStore {
        if let profile = profiles[spaceID] { return profile }
        let profile =
            session.spaces.first(where: { $0.id == spaceID })?.isPrivate == true
            ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: spaceID)
        profiles[spaceID] = profile
        return profile
    }

    func integration(for spaceID: UUID) -> GitHubFolder {
        if let service = integrations[spaceID] { return service }
        let service = GitHubFolder(spaceID: spaceID, store: self)
        integrations[spaceID] = service
        service.start()
        return service
    }

    func pageChanged(_ page: BrowserPage) {
        guard let (s, t) = tabIndex(page.id) else { return }
        if let url = page.url { session.spaces[s].tabs[t].url = url }
        if !page.title.isEmpty { session.spaces[s].tabs[t].title = page.title }
        if let icon = page.favicon, icon.count <= 32_768 { session.spaces[s].tabs[t].favicon = icon }
        changed()
    }

    func pageFinished(_ page: BrowserPage) {
        pageChanged(page)
        guard !session.spaces.contains(where: { $0.id == page.spaceID && $0.isPrivate }),
            let url = page.url, ["https", "http"].contains(url.scheme ?? "")
        else { return }
        let count = session.history.first { $0.spaceID == page.spaceID && $0.url == url }?.count ?? 0
        session.history.removeAll { $0.spaceID == page.spaceID && $0.url == url }
        var visit = BrowserVisit(spaceID: page.spaceID, title: page.title, url: url)
        visit.count = count + 1
        session.history.insert(visit, at: 0)
        changed()
    }

    func clearHistory() {
        session.history.removeAll { $0.spaceID == activeSpace.id }
        changed()
    }

    func updatePreferences(_ update: (inout BrowserPreferences) -> Void) {
        let blocked = preferences.blocksContent
        update(&session.preferences)
        if blocked != preferences.blocksContent {
            for page in pages.values {
                page.applyContentBlocking()
                Task {
                    await page.waitForContentBlocking()
                    page.webView.reload()
                }
            }
        }
        changed()
    }

    func beginDownload(_ download: WKDownload, spaceID: UUID? = nil, restoring id: UUID? = nil) {
        let job = BrowserDownload(download: download, store: self, spaceID: spaceID ?? activeSpace.id, restoring: id)
        downloads[ObjectIdentifier(download)] = job
        runtimeRevision &+= 1
    }

    func unload(_ id: UUID) {
        pages[id]?.checkpointNativeState()
        pages.removeValue(forKey: id)?.invalidate()
        runtimeRevision &+= 1
    }

    // MARK: - Actions - Persistence

    func changed() { owner.changed() }

    @discardableResult func flush() -> Bool { owner.flush() }

    func resumePages() { loadSelection() }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func spaceIndex(_ id: UUID) -> Int {
        session.spaces.firstIndex { $0.id == id } ?? 0
    }

    func tabIndex(_ id: UUID) -> (Int, Int)? {
        for s in session.spaces.indices {
            if let t = session.spaces[s].tabs.firstIndex(where: { $0.id == id }) { return (s, t) }
        }
        return nil
    }
}

extension BrowserStore {
    // MARK: - Actions - Split views

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

    func dismissAddress() {
        addressPresented = false
        pendingSplitSourceID = nil
    }

}
