import AppKit
import SwiftUI

/// Every command Crest's Mac shell can run, as ordinary methods on a value.
///
/// The menu bar used to own these bodies privately, which meant the command
/// palette could only have reached them by copying them. Naming them here — the
/// same shape `MobileBrowserCommandController` already has on iOS — lets the
/// menu bar and the launcher run one implementation.
@MainActor
struct BrowserCommandActions: BrowserNumberedSelectionPerformer {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    /// The shell's windows, which the window commands open; nil where no
    /// window can open, such as outside a shell window.
    let windows: BrowserMacWindows?
    var spaceAccess = BrowserSpaceAccessController()
    /// The window a Quick Window should hand its result back to, when the
    /// command was issued from a focused browser window.
    var targetWindowID: UUID?
    /// The page a Quick Window in front shows, which the page commands act on
    /// in place of the browser window's; nil in a browser window.
    var quickWindowPage: BrowserPage?
    /// Which way the cards are laid out, for the commands that name a side of
    /// the screen. Only the split-card moves read it; see
    /// `BrowserSplitCardMoveDirection`.
    var layoutDirection: LayoutDirection = .leftToRight

    /// The commands the launcher offers on macOS: every one the core offers
    /// in the palette, in the core's order, since this shell performs each.
    static let paletteCommands = ShortcutCommand.all.filter(\.offersInPalette)

    /// The palette's commands and actions in this window. Its settings
    /// pages open through `openSettings`, which the window's Settings
    /// presentation owns.
    func paletteRegistry(
        shortcuts: BrowserShortcutStore?,
        openSettings: @escaping (String) -> Void = { _ in }
    ) -> BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: Self.paletteCommands.filter(isListedInPalette),
            settingsPages: BrowserSettingsDestination.palettePages,
            shortcut: { shortcuts?.shortcut(for: $0) },
            perform: perform,
            openSettings: openSettings,
            switchSpace: selectSpace,
            reopenArchivedTab: reopenArchivedTab,
            copy: copy
        )
    }

    /// Reopens the archived tab `id` in the Space it left, and shows it.
    func reopenArchivedTab(_ id: UUID) {
        browser.restoreArchivedTab(id)
        pages.select()
    }

    /// Whether the page the page commands act on shows a site, whose data
    /// the site commands clear.
    var commandPageShowsSite: Bool {
        commandPage?.live.displayURL?.host()?.isEmpty == false
    }

    /// Clears what the command page's site keeps in `category`, and says how
    /// it went.
    func clearCommandPageSiteData(_ category: BrowsingDataCategory) {
        guard let page = commandPage else { return }
        Task { [chrome] in await page.clearSiteData(category) { chrome.showNotice($0) } }
    }

    /// Copies `text` and says so.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        chrome.showNotice(.copied)
    }

    func perform(_ command: ShortcutCommand) {
        guard windowAllows(command), let action = BrowserMacCommand.of(command), action.isAvailable(self, command)
        else { return }
        action.run(self, command)
    }

    /// Availability belongs to the same command used by menus and keys: the
    /// core says what the window's contents allow, and the command what the
    /// page and its engine can do. In particular, a disabled split shortcut
    /// must leave text selection alone.
    func canPerform(_ command: ShortcutCommand) -> Bool {
        windowAllows(command) && BrowserMacCommand.of(command)?.isAvailable(self, command) == true
    }

    /// Whether what the window shows allows `command`. The core judges a
    /// browser window's contents; a Quick Window shows only its page, so only
    /// the commands on the page run there.
    private func windowAllows(_ command: ShortcutCommand) -> Bool {
        guard quickWindowPage != nil else { return browser.allows(command) }
        return BrowserMacCommand.of(command)?.actsOnPage == true
    }

    /// Whether the palette lists `command` now: the core offers it, and a
    /// command that waits until it can run is able to.
    private func isListedInPalette(_ command: ShortcutCommand) -> Bool {
        guard command.isOffered(in: browser.core.state) else { return false }
        return BrowserMacCommand.of(command)?.waitsInPaletteUntilAvailable != true || canPerform(command)
    }

    /// What the menu bar calls `command` now, when that follows what the
    /// window shows, such as Reader's Show or Hide; nil for its own title.
    func menuTitle(of command: ShortcutCommand) -> LocalizedStringResource? {
        BrowserMacCommand.of(command)?.title(self)
    }

    /// Whether what `command` shows or hides is showing, for a command the
    /// menu bar checks; nil for any other.
    func isOn(_ command: ShortcutCommand) -> Bool? {
        BrowserMacCommand.of(command)?.isOn(self)
    }

    /// Shows the stop or Space a numbered selection leads to.
    func select(_ selection: NumberedSelection) {
        selection.select(on: self)
    }

    /// The page the page commands act on: a Quick Window's in front, or else
    /// the one the window's pool names, a Peek open over the active tab or
    /// the tab's own page.
    var commandPage: BrowserPage? {
        quickWindowPage ?? pages.commandPage
    }

    /// The page the window shows: a Quick Window's in front, or else the
    /// active tab's, even under a Peek. Reader, translation, the inspector,
    /// content blocking and engine moves act on it.
    var shownPage: BrowserPage? {
        quickWindowPage ?? pages.activePage
    }

    /// The Space of the page the window shows: a Quick Window's own, or else
    /// the one the browser window shows.
    var shownPageSpace: SpaceModel? {
        guard let page = quickWindowPage else { return browser.shownSpace }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: page.spaceID, profileID: page.profileID)
        return browser.spaceModel(matching: assignment)
    }

    /// Whether the page the page commands act on has a search to find again.
    var canFindAgain: Bool {
        commandPageSupports(.find) && commandPage?.canFindAgain == true
    }

    /// Whether the page the page commands act on has loaded a document.
    var hasCommandPage: Bool {
        commandPage?.live.documentURL != nil
    }

    var canZoom: Bool {
        commandPageSupports(.zoom) && commandPage?.developerViewport == nil
    }

    /// The same question as `supportsPageCapability` for the page the page
    /// commands act on.
    func commandPageSupports(_ capability: EngineCapability) -> Bool {
        hasCommandPage && commandPage?.pageEngine.registration.supports(capability) == true
    }

    /// Whether the page the window shows has loaded a document its engine can
    /// do `capability` for.
    func supportsPageCapability(_ capability: EngineCapability) -> Bool {
        shownPage?.live.documentURL != nil && shownPage?.pageEngine.registration.supports(capability) == true
    }

    /// The same question as `supportsPageCapability` for commands that are about
    /// the window rather than the document in it, so they stay available in the
    /// moment before a page exists, when the engine new pages open on answers.
    /// The shown page's own engine answers whenever there is one.
    func supportsEngineCapability(_ capability: EngineCapability) -> Bool {
        shownPage?.pageEngine.registration.supports(capability)
            ?? browser.core.state.defaultEngineSupports(capability)
    }

    /// Where each numbered selection command leads right now, per the core.
    var numberedSelections: [ShortcutCommand: NumberedSelection] {
        browser.core.numberedSelections(windowID: browser.windowID)
    }

    // MARK: - Windows

    func openNewTab() {
        chrome.openNewTab(isStartPageSelected: browser.shownTab?.surface == .startPage)
    }

    func openNewWindow() {
        windows?.open(.normal(sourceWindowID: targetWindowID), activation: .key)
    }

    func openBlankWindow() {
        guard !browser.isPrivateBrowsing, let space = browser.shownSpace, !spaceAccess.isLocked(space) else {
            return
        }
        windows?.open(
            .temporary(sourceWindowID: targetWindowID, assignment: BrowserSpaceRuntimeAssignment(space: space)),
            activation: .key)
    }

    func openPrivateWindow() {
        windows?.openPrivateWindow()
    }

    func openQuickWindow() {
        guard let space = browser.shownSpace else { return }
        windows?.openQuickWindow(
            .empty(spaceAssignment: BrowserSpaceRuntimeAssignment(space: space), targetWindowID: targetWindowID))
    }

    func closeKeyWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    /// Closes the selected tab the way the core closes it, or the window when
    /// the core says only the window is left to close.
    func closeTabOrWindow() {
        // A Peek open over the tab closes first, as it is what shows.
        if pages.closePeek() { return }
        guard let selectedTab = browser.shownTab, let space = browser.shownSpace,
            !browser.closingLeavesOnlyTheWindow(selectedTab.id, in: space.id)
        else {
            closeKeyWindow()
            return
        }
        // A saved or pinned tab puts its page away, which the page host
        // follows once the core records it.
        if selectedTab.placement.isDurable {
            if BrowserDurableTabCloseAction(browser: browser, spaceAccess: spaceAccess).perform(
                BrowserTabRuntimeAssignment(
                    tabID: selectedTab.id, spaceID: space.id, profileID: space.profileID
                ))
            {
                pages.select()
            }
        } else if selectedTab.surface == .startPage {
            browser.closeTab(selectedTab.id)
            pages.reconcile()
            pages.select()
        } else {
            archiveSelectedTab()
        }
    }

    // MARK: - Conditions

    var contentBlockingActionTitle: LocalizedStringResource {
        ContentBlockingPolicy.switchTitle(
            for: shownPageSpace?.settings.browsingPreferences.contentBlocking)
    }

    /// The engines the shown page can move to: every registered engine but
    /// its own, so the choice is there before any page opens on the others.
    var pageEngineMoves: [EngineKind] {
        shownPage?.corePage.otherEngines ?? []
    }

    // MARK: - Chrome

    func toggleSidebar() {
        if chrome.columnVisibility == .detailOnly {
            chrome.showSidebar()
        } else {
            chrome.hideSidebar()
        }
    }

    func openLocation() {
        chrome.openLocation(browser.shownTab?.url ?? "")
    }

    /// Opens local documents as ordinary tabs in the Space on screen.
    ///
    /// The archive entry follows the active page's engine, not the platform: a
    /// panel offering a `.webarchive` to Chromium would be offering a document
    /// the engine cannot read.
    func openFile() {
        guard let space = browser.shownSpace else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let format = pages.activePage?.pageEngine.registration.archiveFormat ?? .registered
        let actions = self
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = format.openableContentTypes
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.title = String(localized: "Open File")
            panel.prompt = String(localized: "Open")
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK else { return }
            actions.openLocalDocuments(panel.urls, in: assignment)
        }
    }

    func openLocalDocuments(
        _ urls: [URL],
        in assignment: BrowserSpaceRuntimeAssignment
    ) {
        var selected: URL?
        for url in urls where ExternalLocalDocument.accepts(url) {
            guard browser.openNewTab(url: url, matching: assignment) != nil else { continue }
            selected = url
        }
        guard let selected else { return }
        pages.select()
        pages.load(selected)
        chrome.dismissCommandPalette()
    }

    // MARK: - Page

    /// Moves the shown page to `engine`, which loads what it showed there.
    func movePage(to engine: EngineKind) {
        shownPage?.corePage.move(to: engine)
    }

    /// Translates the whole shown page, which its translation toolbar then
    /// follows.
    func translatePage() {
        shownPage?.translation.present()
    }

    func copyPageLink() {
        guard commandPage?.copyPageLink() == true else { return }
        chrome.showURLCopiedFeedback()
    }

    func copyPageLinkAsMarkdown() {
        guard commandPage?.copyPageLinkAsMarkdown() == true else { return }
        chrome.showURLCopiedFeedback()
    }

    /// Switches content blocking for the Space of the page the window shows.
    func toggleContentBlocking() {
        guard let space = shownPageSpace else { return }
        var preferences = space.settings.browsingPreferences
        preferences.contentBlocking = preferences.contentBlocking.switched
        browser.updateBrowsingPreferences(preferences, in: space.id)
        Task { await pages.reconcileContentBlocking() }
    }

    func zoomIn() {
        guard let page = commandPage, page.zoomIn() else { return }
        chrome.showPageZoomFeedback(page.pageZoom.pageZoomPercentage)
    }

    func zoomOut() {
        guard let page = commandPage, page.zoomOut() else { return }
        chrome.showPageZoomFeedback(page.pageZoom.pageZoomPercentage)
    }

    func resetZoom() {
        guard let page = commandPage, page.resetZoom() else { return }
        chrome.showPageZoomFeedback(page.pageZoom.pageZoomPercentage)
    }

    /// Reloads a Quick Window's page in front or a Peek open over the active
    /// tab, or else the tab, which the pool brings back when its page went.
    func reload(_ mode: BrowserPageReloadMode) {
        if let page = quickWindowPage ?? pages.peekPage {
            page.performReload(mode)
        } else {
            pages.reload(mode)
        }
    }

    // MARK: - Tabs

    func toggleSelectedTabPinned() {
        guard let tab = browser.shownTab, browser.togglePin(tab.id) else { return }
        pages.select()
    }

    func duplicateSelectedTab() {
        guard browser.duplicateSelectedTab() != nil else { return }
        pages.reconcile()
        pages.select()
    }

    func reopenClosedTab() {
        guard browser.reopenClosedTab() else { return }
        pages.select()
    }

    func cleanupCurrentTabs() {
        browser.cleanupCurrentTabs()
        pages.reconcile()
        pages.select()
    }

    func archiveSelectedTab() {
        guard browser.archiveSelectedTab() != nil else { return }
        pages.reconcile()
        pages.select()
    }

    func selectPreviousTab() {
        selectAdjacentTab(.previous)
    }

    func selectNextTab() {
        selectAdjacentTab(.next)
    }

    func selectMostRecentTab() {
        guard browser.showMostRecentTab() else { return }
        pages.select()
    }

    func selectLeastRecentTab() {
        guard browser.showLeastRecentTab() else { return }
        pages.select()
    }

    /// Shows the tab or split a held Most Recent Tab shortcut chose.
    func selectRecentTab(_ item: RecentTabItem) {
        guard browser.showRecentTab(item) else { return }
        pages.select()
    }

    func selectAdjacentTab(_ direction: AdjacentDirection) {
        guard browser.selectAdjacentTab(direction) != nil else { return }
        pages.select()
    }

    /// Shows the tab a numbered command leads to, in the Space this window shows.
    func selectTab(_ tabID: UUID?, in spaceID: UUID) {
        guard let tabID, spaceID == browser.selectedSpaceID else { return }
        browser.selectTab(tabID)
        pages.select()
    }

    // MARK: - Split View

    /// The cards the content area is presenting right now, focused member
    /// included. One element means the selection is an ordinary tab.
    var presentedSplitMembers: [TabStateModel] {
        browser.shownCards
    }

    /// Adds the next eligible tab in the selected tab's own section to its
    /// split, creating the group when there is none yet.
    func splitWithNextTab() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            let candidate = browser.nextSplitJoinCandidate,
            browser.addTabToSplit(
                BrowserTabDragItem(tabID: candidate, spaceID: space.id, profileID: space.profileID),
                joining: selectedTabID,
                at: nil
            )
        else { return }
        pages.select()
    }

    /// Moves focus one card along the presented run and wraps at both ends.
    ///
    /// Focus is selection, so this is `selectTab` and nothing else: the URL
    /// bar, find bar, and every page command follow the selection pipeline they
    /// already followed before splits existed.
    func focusAdjacentSplitCard(offset: Int) {
        let members = presentedSplitMembers
        guard members.count > 1,
            let selectedTabID = browser.shownTab?.id,
            let index = members.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        let count = members.count
        let wrappedIndex = (index + offset % count + count) % count
        browser.selectTab(members[wrappedIndex].id)
        pages.select()
    }

    /// The on-screen direction resolved against this shell's layout, so a menu
    /// item and the palette ask the same question the same way.
    func canMoveFocusedSplitCard(
        _ direction: BrowserSplitCardMoveDirection
    ) -> Bool {
        canMoveFocusedSplitCard(
            offset: direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    func moveFocusedSplitCard(_ direction: BrowserSplitCardMoveDirection) {
        moveFocusedSplitCard(
            offset: direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    /// Whether the focused card has anywhere to go `offset` slots along.
    func canMoveFocusedSplitCard(offset: Int) -> Bool {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id)
        else { return false }
        return browser.canMoveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Slides the focused card along its split run.
    ///
    /// No `pages.select(session:)` afterwards, unlike every other split command
    /// here: the selection is the same tab and the same set of cards is on
    /// screen, so there is nothing for the pool to reconcile. The column row
    /// reads member order straight from the session and re-lays itself out.
    func moveFocusedSplitCard(offset: Int) {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id)
        else { return }
        browser.moveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Drops the focused card out of its split and leaves it an ordinary tab.
    func removeSelectedTabFromSplit() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.removeTabFromSplit(
                selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select()
    }

    /// "Separate All Tabs": every card in the presented split becomes a tab.
    func separateSplitTabs() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.dissolveSplit(
                containing: selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select()
    }

    // MARK: - Spaces

    func selectPreviousSpace() {
        selectAdjacentSpace(.previous)
    }

    func selectNextSpace() {
        selectAdjacentSpace(.next)
    }

    func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) {
        guard browser.selectAdjacentSpace(direction) != nil else { return }
        pages.selectSpace(in: browser)
    }

    func selectSpace(_ spaceID: UUID) {
        browser.selectSpace(spaceID)
        pages.selectSpace(in: browser)
    }
}
