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
    let sidebarReorder = BrowserSidebarReorderState()
    let sidebarFolders = BrowserSidebarFolderVisibility()
    var sidebarSpaceStep: Int?
    var sidebarSpaceTransitioning = false
    @ObservationIgnored var sidebarScrollOffsets: [UUID: CGFloat] = [:]
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
        sidebarRevealed || sidebarEditorPresented || isResizingSidebar || isDragging
            || editingTabID != nil || editingFolderID != nil || selectedTab == nil
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
        if addressCreatesTab || selectedTab == nil {
            let source = pendingSplitSourceID
            guard let id = open(url) else { return }
            addressPresented = false
            pendingSplitSourceID = nil
            if let source { split(source, with: id) }
        } else if let id = selectedTab?.id {
            addressPresented = false
            navigate(url, in: id)
        }
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
        let previousPage = activePage
        prepareSidebarSpaceChange(session.spaces[space].id)
        windowState.spaceID = session.spaces[space].id
        if !session.spaces[space].isPrivate { session.selectedSpaceID = session.spaces[space].id }
        setSelectedTab(id, in: session.spaces[space].id)
        utility = nil
        findsPage = false
        loadSelection()
        if let page = activePage {
            page.contentBlocker.controller.didActivateTab(
                page, previousActiveTab: previousPage?.spaceID == page.spaceID ? previousPage : nil)
        }
        let visible = owner.visiblePageIDs
        for page in previousPages where !visible.contains(page.id) {
            page.lastSelected = Date()
            page.beginPictureInPicture()
        }
        changed()
    }

    func selectSpace(_ id: UUID, step: Int? = nil) {
        guard session.spaces.contains(where: { $0.id == id }), id != activeSpace.id else { return }
        prepareSidebarSpaceChange(id, step: step)
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

    private func prepareSidebarSpaceChange(_ id: UUID, step: Int? = nil) {
        guard id != activeSpace.id,
            let origin = session.spaces.firstIndex(where: { $0.id == activeSpace.id }),
            let destination = session.spaces.firstIndex(where: { $0.id == id })
        else { return }
        sidebarSpaceStep = step ?? (abs(destination - origin) == 1 ? destination - origin : nil)
        sidebarSpaceTransitioning =
            sidebarSpaceStep != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && owner.sidebarDrag.payload == nil
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
        guard !isClosed else { return nil }
        if let page = pages[id] { return page }
        guard let (s, t) = tabIndex(id) else { return nil }
        let tab = session.spaces[s].tabs[t]
        guard !tab.isSettings, tab.url != nil else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile(for: session.spaces[s].id)
        let page = BrowserPage(id: id, spaceID: session.spaces[s].id, configuration: configuration, owner: self)
        page.hostingWindowID = self.id
        pages[id] = page
        page.contentBlocker.controller.didOpenTab(page)
        runtimeRevision &+= 1
        page.restore(tab)
        return page
    }

    func selectNextLoaded(excluding id: UUID) {
        let next = sidebarOrder.first { $0.id != id && (pages[$0.id] != nil || $0.isSettings) }
        setSelectedTab(next?.id, in: activeSpace.id)
        runtimeRevision &+= 1
    }

    func isLoaded(_ tab: BrowserTab) -> Bool {
        _ = runtimeRevision
        return pages[tab.id] != nil || tab.isSettings
    }

    // MARK: - Actions - Pages

    func pageChanged(_ page: BrowserPage) {
        guard let (s, t) = tabIndex(page.id) else { return }
        if let url = page.url { session.spaces[s].tabs[t].url = url }
        if !page.title.isEmpty { session.spaces[s].tabs[t].title = page.title }
        if let icon = page.favicon, icon.count <= 32_768 { session.spaces[s].tabs[t].favicon = icon }
        changed()
    }

    func unload(_ id: UUID) {
        pages[id]?.checkpointNativeState()
        pages.removeValue(forKey: id)?.invalidate()
        owner.media?.refresh()
        runtimeRevision &+= 1
    }

    func dismissAddress() {
        addressPresented = false
        pendingSplitSourceID = nil
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
