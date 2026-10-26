import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserRootModel {
    typealias SidebarMorphWait = @MainActor (Duration) async throws -> Void

    let browser: BrowserStore
    let sidebarInteraction: BrowserSidebarInteractionState
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    private let layoutPersistence: BrowserWindowLayoutPersistence
    let startupBehavior: StartupBehavior

    var address = ""
    var isAddressEditing = false
    /// Keep binding construction outside view evaluation: constructing a
    /// closure-backed binding reads its initial value. Reuse it so containers
    /// forwarding the binding do not observe the address themselves.
    @ObservationIgnored private(set) lazy var addressBinding = Binding<String>(
        get: { @MainActor [weak self] in self?.address ?? "" },
        set: { @MainActor [weak self] address in
            guard let self, self.address != address else { return }
            self.address = address
        }
    )
    @ObservationIgnored private(set) lazy var isAddressEditingBinding = Binding<Bool>(
        get: { @MainActor [weak self] in self?.isAddressEditing ?? false },
        set: { @MainActor [weak self] isEditing in
            guard let self, self.isAddressEditing != isEditing else { return }
            self.isAddressEditing = isEditing
        }
    )
    var isPrepared = false
    @ObservationIgnored private var isPreparingBrowser = false
    /// The window's chrome keeps it, so a command that presents a sidebar list
    /// knows whether the sidebar is already on screen.
    var isFloatingSidebarPresented: Bool {
        get { chrome.isFloatingSidebarPresented }
        set { chrome.isFloatingSidebarPresented = newValue }
    }
    private(set) var isSidebarMorphing: Bool {
        get { observed(\.isSidebarMorphingStorage, as: \.isSidebarMorphing) }
        set { publish(newValue, into: \.isSidebarMorphingStorage, as: \.isSidebarMorphing) }
    }
    @ObservationIgnored private var isSidebarMorphingStorage = false
    /// True while the page row is making the sidebar's dock available, before
    /// the persistent floating card adopts its docked appearance.
    private(set) var isSidebarApproachingDock: Bool {
        get { observed(\.isSidebarApproachingDockStorage, as: \.isSidebarApproachingDock) }
        set { publish(newValue, into: \.isSidebarApproachingDockStorage, as: \.isSidebarApproachingDock) }
    }
    @ObservationIgnored private var isSidebarApproachingDockStorage = false
    private(set) var isSidebarSurfaceHovered = false
    /// Whether the floating sidebar came out because the pointer reached the
    /// window edge, rather than from a click, command or page request.
    private(set) var isFloatingSidebarRevealedByPointer = false
    private var sidebarMorphRevision = 0
    /// Cancels or awaits the current sidebar transition.
    @ObservationIgnored private(set) var sidebarMorphTask: Task<Void, Never>?
    /// Injectable phase timing for sidebar transitions.
    @ObservationIgnored
    var sidebarMorphWait: SidebarMorphWait = { try await Task.sleep(for: $0) }
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
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: StartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        self.pages = pages
        self.chrome = chrome
        self.spaceAccess = spaceAccess
        self.windowState = windowState
        layoutPersistence = BrowserWindowLayoutPersistence(windowState: windowState)
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
        _ = addressBinding
        _ = isAddressEditingBinding
        registerForNotices()
    }

    private func registerForNotices() {
        BrowserNoticeCenter.shared.register(chrome) { [weak self] in self?.isWindowFocused == true }
    }
}

// MARK: - Lifecycle

extension BrowserRootModel {
    func prepareBrowser() async {
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: chrome.columnVisibility != .detailOnly
        )
        guard !isPrepared, !isPreparingBrowser else { return }
        isPreparingBrowser = true
        defer { isPreparingBrowser = false }

        // Apply the launch choice before yielding to rule-list startup.
        // Once the window accepts input, the user's current selection takes precedence.
        if startupBehavior == .showStartPage {
            browser.presentStartPageForLaunch()
            address = ""
        }
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

    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess()
    }

    func reloadContentBlocking() {
        guard isPrepared else { return }
        Task { await pages.reloadContentBlocking() }
    }

    func relockProtectedSpaces(_ spaceIDs: Set<UUID>) {
        // The Space itself, not just its ID: relocking has to reach the
        // profile its archived tab state is filed under, and that state
        // outlives the resident pages an ID alone can find.
        for space in browser.spaceModels where spaceIDs.contains(space.id) {
            pages.relockProtectedSpace(space)
        }
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
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space),
            let assignment = browser.shownTabAssignment
        else { return nil }
        return pages.activePage(matching: assignment)
    }

    var windowTitle: String {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space), let tab = browser.shownTab else {
            return ProductIdentity.name
        }
        return BrowserWindowTitle.resolve(tab: tab, page: selectedPage)
    }

    /// Shows the address the page of the tab the window shows reads in the
    /// core, or its tab's, in the address field, unless the person is editing
    /// it, the Space is locked or no page shows that tab; another window's or
    /// Space's page never replaces what the field holds.
    func synchronizePageMetadata() {
        guard !isAddressEditing, !selectedSpaceIsLocked, let page = selectedPage else { return }
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

    var selectedSpaceIsLocked: Bool {
        guard let space = browser.shownSpace else { return false }
        return spaceAccess.isLocked(space)
    }

    var lockedSpaceIDs: Set<UUID> {
        Set(browser.spaceModels.filter(spaceAccess.isLocked).map(\.id))
    }

    func openNewTab() {
        chrome.openNewTab(isStartPageSelected: browser.shownTab?.surface == .startPage)
    }

    /// Loads what the person typed, which the core resolves by the Space's
    /// address rules. A native Settings or Getting Started tab has no page:
    /// the core gives it the address first, and selection builds its page and
    /// loads it there.
    func submitAddress() {
        let input = address
        if browser.shownTab?.surface.showsPage == false {
            guard browser.navigateSelectedTab(to: input) else { return }
            pages.select()
        } else {
            pages.select()
            guard pages.navigate(to: input) else { return }
        }
        address = (selectedPage?.live.displayURL ?? browser.shownTab?.address)?.absoluteString ?? input
        isAddressEditing = false
        AddressFocusAction.resign()
    }

    func synchronizeAfterSelectionChange() {
        guard isPrepared else { return }
        isAddressEditing = false
        // A split card already on screen may hold the focus of the click
        // that selected it.
        AddressFocusAction.resign(
            keepingFocusIn: browser.shownTabAssignment.flatMap(pages.presentedPage(matching:))?.nativeView)
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        guard isPrepared else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        if selectedSpaceIsLocked || !pages.isPresentingSelection() {
            if selectedSpaceIsLocked {
                pages.deactivatePagePresentation()
            } else {
                pages.selectSpace(in: browser)
            }
            showAddressAtOnce(selectedSpaceIsLocked ? "" : browser.shownTab?.url ?? "")
            return
        }
        showAddressAtOnce(browser.shownTab?.url ?? "")
    }

    func synchronizeAfterLockChange() {
        guard isPrepared else { return }
        synchronizeSelection()
    }

    func synchronizeSelection() {
        browser.consumeMovedTabActivation()
        guard !selectedSpaceIsLocked else {
            pages.deactivatePagePresentation()
            showAddressAtOnce("")
            return
        }
        if browser.shownTab?.surface == .startPage, browser.shownCards.count < 2 {
            pages.leavePagePresentation()
        } else {
            pages.select()
        }
        showAddressAtOnce(browser.shownTab?.url ?? "")
    }

    /// Shows another tab's or Space's address the way browsers switch tabs:
    /// at once. The address band fades in an address a navigation changes,
    /// and that fade, run on every switch, redraws the band each frame for
    /// its whole length.
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
        BrowserSidebarPresentation(
            columnVisibility: chrome.columnVisibility,
            isFloatingSidebarPresented: isFloatingSidebarPresented,
            isPageFullscreen: chrome.revealsSidebarOverFullscreenPage
        )
    }

    var sidebarWidth: CGFloat {
        sidebarWidthTransaction.width
    }

    var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { self.sidebarWidthTransaction.width },
            set: { self.sidebarWidthTransaction.resize(to: $0) }
        )
    }

    func restoreSidebarWidth(_ width: CGFloat) {
        layoutPersistence.restoreSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

    func commitSidebarWidth(_ width: CGFloat) -> CGFloat? {
        layoutPersistence.commitSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

    func hideSidebar(reduceMotion: Bool) {
        chrome.utilityPresentation.dismiss()
        isFloatingSidebarRevealedByPointer = false
        guard !reduceMotion else {
            cancelSidebarMorph()
            isFloatingSidebarPresented = isSidebarSurfaceHovered
            chrome.hideSidebar()
            return
        }

        let revision = beginSidebarMorph()
        sidebarMorphTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                !Task.isCancelled,
                self.sidebarMorphRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.sidebarMorph, reduceMotion)
            ) {
                self.isFloatingSidebarPresented = true
                self.chrome.hideSidebar()
            }
            try? await self.sidebarMorphWait(
                CrestMotion.sidebarMorphCompletionDelay
            )
            guard !Task.isCancelled,
                self.finishSidebarMorph(revision),
                self.sidebarPresentation == .floating
            else { return }
            self.dismissFloatingSidebarIfInteractionAllows(
                reduceMotion: reduceMotion
            )
        }
    }

    func toggleSidebar(reduceMotion: Bool) {
        sidebarPresentation.sidebarToggleAction.perform(on: self, reduceMotion: reduceMotion)
    }

    func dockSidebar(reduceMotion: Bool) {
        isFloatingSidebarRevealedByPointer = false
        guard !reduceMotion else {
            cancelSidebarMorph()
            isFloatingSidebarPresented = false
            chrome.showSidebar()
            return
        }
        let revision = beginSidebarMorph()
        sidebarMorphTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                !Task.isCancelled,
                self.sidebarMorphRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(
                    CrestMotion.sidebarDockApproach,
                    reduceMotion
                )
            ) {
                self.isSidebarApproachingDock = true
            }
            try? await self.sidebarMorphWait(
                CrestMotion.sidebarDockApproachCompletionDelay
            )
            guard !Task.isCancelled,
                self.sidebarMorphRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(
                    CrestMotion.sidebarDockAttachment,
                    reduceMotion
                )
            ) {
                self.isFloatingSidebarPresented = false
                self.chrome.showSidebar()
            }
            try? await self.sidebarMorphWait(
                CrestMotion.sidebarDockAttachmentCompletionDelay
            )
            guard !Task.isCancelled,
                self.sidebarMorphRevision == revision
            else { return }
            withTransaction(Transaction(animation: nil)) {
                self.isSidebarApproachingDock = false
            }
            _ = self.finishSidebarMorph(revision)
        }
    }

    func presentFloatingSidebar(reduceMotion: Bool) {
        guard sidebarPresentation != .docked else { return }
        cancelSidebarMorph()
        withAnimation(
            accessibleAnimation(CrestMotion.floatingPane, reduceMotion)
        ) {
            isFloatingSidebarPresented = true
        }
    }

    /// Presents the floating sidebar for a pointer that reached the window
    /// edge. Leaving the window counts as leaving the sidebar from then on,
    /// even before the pointer first reaches the card sliding in under it.
    func revealFloatingSidebarFromPointer(reduceMotion: Bool) {
        presentFloatingSidebar(reduceMotion: reduceMotion)
        guard sidebarPresentation == .floating else { return }
        isFloatingSidebarRevealedByPointer = true
    }

    func dismissFloatingSidebar(reduceMotion: Bool) {
        cancelSidebarMorph()
        isFloatingSidebarRevealedByPointer = false
        if sidebarPresentation == .floating {
            chrome.utilityPresentation.dismiss()
        }
        withAnimation(
            accessibleAnimation(CrestMotion.sidebarRetreat, reduceMotion)
        ) {
            isFloatingSidebarPresented = false
        }
        isSidebarSurfaceHovered = false
    }

    func sidebarSurfaceHoverChanged(
        _ isHovering: Bool,
        reduceMotion: Bool
    ) {
        isSidebarSurfaceHovered = isHovering
        guard sidebarPresentation == .floating, !isHovering else { return }
        dismissFloatingSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    func sidebarInteractionChanged(
        _ isActive: Bool,
        reduceMotion: Bool
    ) {
        guard !isActive else { return }
        dismissFloatingSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    /// Follows whether the active page shows alone with the sidebar hover area
    /// live. A sidebar floating over the page goes with it, so the shell comes
    /// back as the person left it.
    func fullscreenSidebarRevealChanged(_ reveals: Bool) {
        guard chrome.revealsSidebarOverFullscreenPage != reveals else { return }
        cancelSidebarMorph()
        chrome.utilityPresentation.dismiss()
        withTransaction(Transaction(animation: nil)) {
            isFloatingSidebarPresented = false
            chrome.revealsSidebarOverFullscreenPage = reveals
        }
        isSidebarSurfaceHovered = false
    }

    /// A command can put the floating sidebar away without going through
    /// `dismissFloatingSidebar`, and whatever revealed it last no longer applies.
    func floatingSidebarPresentationChanged() {
        guard !isFloatingSidebarPresented else { return }
        isFloatingSidebarRevealedByPointer = false
    }

    func columnVisibilityChanged(reduceMotion: Bool) {
        guard chrome.columnVisibility != .detailOnly else {
            chrome.utilityPresentation.dismiss()
            return
        }
        guard !isSidebarMorphing else { return }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func beginSidebarMorph() -> Int {
        sidebarMorphTask?.cancel()
        sidebarMorphTask = nil
        sidebarMorphRevision += 1
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = true
        }
        return sidebarMorphRevision
    }

    private func dismissFloatingSidebarIfInteractionAllows(
        reduceMotion: Bool
    ) {
        guard !isSidebarMorphing,
            !isSidebarSurfaceHovered,
            !chrome.utilityPresentation.isSidebarInteractionActive
        else { return }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }

    @discardableResult
    private func finishSidebarMorph(_ revision: Int) -> Bool {
        guard revision == sidebarMorphRevision else { return false }
        sidebarMorphTask = nil
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = false
        }
        return true
    }

    private func cancelSidebarMorph() {
        sidebarMorphTask?.cancel()
        sidebarMorphTask = nil
        sidebarMorphRevision += 1
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = false
            isSidebarApproachingDock = false
        }
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
    /// Whether this window shows its command palette: one was asked for, and
    /// the selected tab, or the empty selection of an unlocked Space, can act
    /// on it.
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
            accessController: spaceAccess,
            didSelectTab: { [weak self] in
                guard let self else { return }
                self.pages.select()
                self.address = self.browser.shownTab?.url ?? ""
            }
        )
    }

    /// Which side of the field-to-palette morph holds the shared identity. The
    /// field is on screen whenever the sidebar is, docked or floating.
    func commandPaletteHandoff(reduceMotion: Bool) -> BrowserCommandPaletteHandoff {
        .resolve(
            isPaletteShown: isCommandPaletteShown,
            isFieldOnScreen: sidebarPresentation.showsSidebar,
            animates: BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
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
            spaceAccess: spaceAccess,
            targetWindowID: windowState?.id,
            layoutDirection: layoutDirection,
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
        browser.isPaletteSourceAvailable(source, accessController: spaceAccess)
    }

    @discardableResult
    func selectPaletteTab(
        from source: BrowserTabRuntimeAssignment,
        to target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = browser.paletteTarget(target, from: source, accessController: spaceAccess)
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
            browser.isPaletteSourceAvailable(source, accessController: spaceAccess)
        else { return false }
        return opening.open(url, from: source, with: BrowserMacPaletteOpener(model: self, mode: mode, windows: windows))
    }

    /// Loads `url` in the page the window shows and shows it in the address field.
    fileprivate func showLoading(_ url: URL) {
        pages.select()
        pages.load(url)
        address = url.absoluteString
    }
}

/// How the Mac window opens an address from its palette: in place of the
/// source tab, or in a new tab when the palette opened for one; in a new tab
/// behind or in front; beside the source in Split View; or in a Quick Window
/// that hands its result back to this window.
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

    func openInQuickWindow(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        guard let windows else { return false }
        windows.openQuickWindow(
            BrowserQuickWindowRequest(
                url: url,
                spaceAssignment: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                targetWindowID: model.windowState?.id))
        return true
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

// MARK: - Downloads

extension BrowserRootModel {
    var selectedUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}

extension BrowserRootModel: BrowserStoreFirstObservable {}

extension BrowserRootModel: BrowserSidebarToggleTarget {}
