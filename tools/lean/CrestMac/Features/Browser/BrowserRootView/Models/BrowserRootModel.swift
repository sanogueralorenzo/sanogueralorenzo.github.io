import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserRootModel {
    let browser: BrowserStore
    let sidebarInteraction: BrowserSidebarInteractionState
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let windowState: BrowserWindowStateStore?
    private let layoutPersistence: BrowserWindowLayoutPersistence

    var address = ""
    var isPrepared = false
    @ObservationIgnored private var isPreparingBrowser = false
    /// Empty Spaces keep navigation discoverable; populated Spaces follow this window's hover and utility state.
    var isSidebarPresented: Bool {
        chrome.isSidebarPresented || isSidebarSurfaceHovered || hasNoSidebarTabs
    }

    private var hasNoSidebarTabs: Bool {
        guard let space = browser.shownSpace else { return false }
        return space.tabs.models.allSatisfy(\.isStartPage)
    }
    private(set) var isSidebarSurfaceHovered = false
    private(set) var isSidebarRevealedByPointer = false
    var isWindowFocused: Bool {
        get { observed(\.isWindowFocusedStorage, as: \.isWindowFocused) }
        set { publish(newValue, into: \.isWindowFocusedStorage, as: \.isWindowFocused) }
    }
    @ObservationIgnored private var isWindowFocusedStorage = true
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live widths stay local until the divider drag commits.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: [1]
    )
    /// The window owns the lift so its preview can outlive the source surface.
    let splitCardLift = BrowserSplitCardLiftState()
    /// This window's extension side panel, if one is open. Transient by
    /// construction: nothing about it reaches the session, disk or sync.
    let extensionSidePanel = BrowserExtensionSidePanelHost()

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        windowState: BrowserWindowStateStore?,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        self.pages = pages
        self.chrome = chrome
        self.windowState = windowState
        layoutPersistence = BrowserWindowLayoutPersistence(windowState: windowState)
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
        registerForNotices()
    }

    private func registerForNotices() {
        BrowserNoticeCenter.shared.register(chrome) { [weak self] in self?.isWindowFocused == true }
    }
}

// MARK: - Lifecycle

extension BrowserRootModel {
    func prepareBrowser() async {
        windowState?.captureSidebar(width: Double(sidebarWidth))
        guard !isPrepared, !isPreparingBrowser else { return }
        isPreparingBrowser = true
        defer { isPreparingBrowser = false }

        await pages.prepareContentBlocking()
        isPrepared = true
        synchronizeSelection()
    }

    func reconcilePages() {
        pages.reconcile()
    }

    func hostWindowFocusChanged(_ isFocused: Bool) {
        // Window scenes route native key-window notifications directly. A new
        // root's initial SwiftUI focus value must not claim a shared page.
        guard !pages.publishesPageMetadataCentrally else { return }
        pages.setWindowFocused(isFocused)
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons()
    }

    func reconcileContentBlocking() {
        guard isPrepared else { return }
        Task { await pages.reconcileContentBlocking() }
    }

    func reloadContentBlocking() {
        guard isPrepared else { return }
        Task { await pages.reloadContentBlocking() }
    }

}

// MARK: - Bindings

extension BrowserRootModel {
    var isWindowFocusedBinding: Binding<Bool> {
        Binding(
            get: { self.isWindowFocused },
            set: { isFocused in
                guard self.isWindowFocused != isFocused else { return }
                self.isWindowFocused = isFocused
                if isFocused { self.registerForNotices() }
            }
        )
    }
}

// MARK: - Page Synchronization

extension BrowserRootModel {
    private var selectedPage: BrowserPage? {
        guard browser.shownSpace != nil,
            let assignment = browser.shownTabAssignment
        else { return nil }
        return pages.activePage(matching: assignment)
    }

    var windowTitle: String {
        guard browser.shownSpace != nil, let tab = browser.shownTab else {
            return ProductIdentity.name
        }
        return BrowserWindowTitle.resolve(tab: tab, page: selectedPage)
    }

    func synchronizePageMetadata() {
        guard let page = selectedPage else { return }
        address = (page.live.displayURL ?? browser.shownTab?.address)?.absoluteString ?? ""
    }

}

// MARK: - Navigation

extension BrowserRootModel {
    /// Distinguishes Space changes from tab changes.
    var selectionSnapshot: BrowserRootSelectionSnapshot {
        BrowserRootSelectionSnapshot(
            tabID: browser.shownTab?.id,
            spaceID: browser.selectedSpaceID
        )
    }

    func openNewTab() {
        chrome.openNewTab(isStartPageSelected: browser.shownTab?.surface == .startPage)
    }

    func synchronizeAfterSelectionChange() {
        guard isPrepared else { return }
        // A split card already on screen may hold the focus of the click
        // that selected it.
        AddressFocusAction.resign(
            keepingFocusIn: browser.shownTabAssignment.flatMap(pages.presentedPage(matching:))?.nativeView)
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        guard isPrepared else { return }
        AddressFocusAction.resign()
        if !pages.isPresentingSelection() {
            pages.selectSpace(in: browser)
            showAddressAtOnce(browser.shownTab?.url ?? "")
            return
        }
        showAddressAtOnce(browser.shownTab?.url ?? "")
    }

    func synchronizeSelection() {
        browser.consumeMovedTabActivation()
        if browser.shownTab?.surface == .startPage, browser.shownCards.count < 2 {
            pages.leavePagePresentation()
        } else {
            pages.select()
        }
        showAddressAtOnce(browser.shownTab?.url ?? "")
    }

    /// Keeps the palette's current address in step with tab and Space selection.
    private func showAddressAtOnce(_ value: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { address = value }
    }

    func handleAuxiliaryMouseAction(
        _ action: BrowserSidebarMouseButtonAction
    ) {
        guard browser.selectAdjacentSpace(action.spaceDirection) != nil else { return }
        pages.selectSpace(in: browser)
    }
}

// MARK: - Sidebar

extension BrowserRootModel {
    var sidebarPresentation: BrowserSidebarPresentation {
        isSidebarPresented ? .floating : .collapsed
    }

    func sidebarPresentationChanged() {
        guard !isSidebarPresented else { return }
        isSidebarRevealedByPointer = false
        isSidebarSurfaceHovered = false
    }

    func revealSidebarFromPointer(reduceMotion: Bool) {
        isSidebarRevealedByPointer = true
        withAnimation(accessibleAnimation(CrestMotion.floatingPane, reduceMotion)) {
            chrome.showSidebar()
        }
    }

    func sidebarSurfaceHoverChanged(_ isHovering: Bool, reduceMotion: Bool) {
        isSidebarSurfaceHovered = isHovering
        guard !isHovering else { return }
        dismissSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    func sidebarInteractionChanged(_ isActive: Bool, reduceMotion: Bool) {
        guard !isActive else { return }
        dismissSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    private func dismissSidebarIfInteractionAllows(reduceMotion: Bool) {
        guard !isSidebarSurfaceHovered,
            !chrome.utilityPresentation.isSidebarInteractionActive
        else { return }
        isSidebarRevealedByPointer = false
        withAnimation(accessibleAnimation(CrestMotion.floatingPane, reduceMotion)) {
            chrome.hideSidebar()
        }
    }

    var sidebarWidth: CGFloat {
        sidebarWidthTransaction.width
    }

    func restoreSidebarWidth(_ width: CGFloat) {
        layoutPersistence.restoreSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

}

// MARK: - Split Layout

extension BrowserRootModel {
    /// The cards the content area presents, as the window's read model
    /// publishes them, so SwiftUI observes what changes when membership does.
    var presentedSplitMembers: [TabStateModel] {
        browser.shownCards
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no
    /// layout to store.
    var presentedSplitGroupID: UUID? {
        browser.shownSpace.flatMap(browser.shownSplitGroupID(in:))
    }

    var splitWidthTransactionBinding: Binding<BrowserSplitWidthTransaction> {
        Binding(
            get: { self.splitWidthTransaction },
            set: { self.splitWidthTransaction = $0 }
        )
    }

    func seedSplitColumnFractions() {
        layoutPersistence.seedSplitLayout(
            groupID: presentedSplitGroupID, memberCount: presentedSplitMembers.count,
            transaction: &splitWidthTransaction
        )
    }

    func commitSplitColumnFractions(_ fractions: [Double]) {
        layoutPersistence.commitSplitLayout(fractions, groupID: presentedSplitGroupID)
    }

    func focusSplitCard(_ tabID: UUID) {
        guard tabID != browser.shownTab?.id,
            presentedSplitMembers.contains(where: { $0.id == tabID })
        else { return }
        browser.selectTab(tabID)
    }
}

// MARK: - Command Palette

extension BrowserRootModel {
    var isCommandPaletteShown: Bool {
        guard chrome.isCommandPalettePresented else { return false }
        if let source = selectedTabAssignment {
            return isPaletteSourceAvailable(source)
        }
        return emptySelectionPaletteActions?.isAvailable == true
    }

    /// The New Tab actions of a selected Space with no tab selected.
    var emptySelectionPaletteActions: BrowserEmptySelectionPaletteActions? {
        guard let space = browser.shownSpace, browser.shownTab == nil else { return nil }
        return BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser,
            didSelectTab: { [weak self] in
                guard let self else { return }
                self.pages.select()
                self.address = self.browser.shownTab?.url ?? ""
            }
        )
    }

    var selectedTabAssignment: BrowserTabRuntimeAssignment? {
        browser.shownTabAssignment
    }

    /// The commands this window's palettes offer, the overlay's and every
    /// Start Page's, run by the same routes as the menu bar.
    func paletteRegistry(
        windows: BrowserMacWindows?,
        layoutDirection: LayoutDirection,
        shortcuts: BrowserShortcutStore?,
        settings: BrowserSpaceSettingsPresentationState? = nil
    ) -> BrowserCommandPaletteCommandRegistry {
        BrowserCommandActions(
            browser: browser,
            pages: pages,
            chrome: chrome,
            windows: windows,
            targetWindowID: windowState?.id,
            layoutDirection: layoutDirection
        )
        .paletteRegistry(shortcuts: shortcuts) { [weak self] name in self?.openPaletteSettings(name, in: settings) }
    }

    /// Opens Settings at the page the settings call `name`, which `settings`
    /// presents.
    func openPaletteSettings(_ name: String, in settings: BrowserSpaceSettingsPresentationState?) {
        guard let destination = BrowserSettingsDestination.all.first(where: { $0.name == name }),
            let space = browser.shownSpace
        else { return }
        settings?.present(destination, assignment: BrowserSpaceRuntimeAssignment(space: space))
        browser.openSettings()
        pages.select()
    }

    func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        browser.isPaletteSourceAvailable(source)
    }

    @discardableResult
    func selectPaletteTab(
        from source: BrowserTabRuntimeAssignment,
        to target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = browser.paletteTarget(target, from: source)
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select()
        address = browser.shownTab?.url ?? ""
        return true
    }

    /// Opens `url` from the palette where `opening` says, from `source`, once
    /// the source's Space may still act.
    @discardableResult
    func openPaletteURL(
        _ url: URL,
        mode: BrowserCommandPaletteMode,
        from source: BrowserTabRuntimeAssignment,
        opening: BrowserCommandPaletteOpening = .here,
        windows: BrowserMacWindows? = nil
    ) -> Bool {
        guard
            browser.isPaletteSourceAvailable(source)
        else { return false }
        return opening.open(url, from: source, with: BrowserMacPaletteOpener(model: self, mode: mode, windows: windows))
    }

    /// Loads `url` in the page the window shows and updates the palette address.
    fileprivate func showLoading(_ url: URL) {
        pages.select()
        pages.load(url)
        address = url.absoluteString
    }
}

@MainActor
private struct BrowserMacPaletteOpener: BrowserCommandPaletteOpener {
    let model: BrowserRootModel
    let mode: BrowserCommandPaletteMode
    let windows: BrowserMacWindows?

    func openHere(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        if mode == .newTab { return openTab(url, from: source, selecting: true) }
        model.browser.navigateSelectedTab(to: url.absoluteString)
        model.showLoading(url)
        return true
    }

    func openTab(_ url: URL, from source: BrowserTabRuntimeAssignment, selecting: Bool) -> Bool {
        guard selecting else { return model.browser.openBackgroundTab(url: url, in: source.spaceID) != nil }
        guard model.browser.openAddress(url, in: source.spaceID) else { return false }
        model.showLoading(url)
        return true
    }

    func openInSplit(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
        return model.browser.openLinkInSplit(url: url, joining: source.tabID, matching: assignment) != nil
    }

}

// MARK: - Animation

extension BrowserRootModel {
    func accessibleAnimation(
        _ animation: Animation,
        _ reduceMotion: Bool
    ) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

extension BrowserRootModel: BrowserStoreFirstObservable {}
