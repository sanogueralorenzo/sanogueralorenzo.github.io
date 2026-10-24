import Foundation

/// A window's owner of the pages its workspace's host keeps: a Mac window's
/// page pool, or an iPhone or iPad scene's page store. What every owner does
/// the same way lives here, over the host and the window's read model; each
/// platform keeps only presentation and what its windowing needs.
@MainActor
protocol BrowserPageOwner: AnyObject, BrowserTabCopying, BrowserTabLinkProviding, BrowserSpaceDataDeleting {
    /// The window whose read model the owner follows.
    var browser: BrowserStore { get }
    /// The pages the owner's workspace keeps.
    var host: BrowserPageHost { get }
    /// The focused card's page, which the page commands act on.
    var activePage: BrowserPlatformPage? { get }
    /// Every tab whose page some window over the host presents now.
    var presentedTabIDsAcrossWindows: Set<UUID> { get }
    /// The built-in content blocking the owner applies to its pages.
    var contentBlocking: BrowserContentBlockingController { get }
    /// The certificate exceptions people accepted for the owner's pages, by
    /// profile.
    var serverTrustOverrides: BrowserServerTrustOverrideStore { get }
    /// Whether every page keeps its website data in memory only.
    var usesEphemeralWebsiteDataStores: Bool { get }
    var downloadCenter: BrowserDownloadCenter { get }
    var permissionCenter: BrowserSitePermissionCenter { get }

    /// A lease on a page the core opens in `space` for a transient request,
    /// on `opener`'s engine when another page opened it.
    func makeTransientPageLease(
        url: URL,
        in space: SpaceModel,
        presentation: TransientPresentation,
        engineNavigation: BrowserEngineNavigation?,
        opener: UUID?,
        onUserActivity: @escaping () -> Void,
        onDownloadOnlyNavigation: (() -> Void)?
    ) -> BrowserPlatformTransientPageLease?

    /// Hosts `opened`, a page the core opened itself for `tab` in `space`, as
    /// the tab's resident page, and brings the tab forward when `shows`.
    func hostAdoptedPage(_ opened: Engines.OpenedPage, as tab: BrowserPageTab, in space: SpaceModel, shows: Bool)
}

// MARK: - Pages the core opened or put away

extension BrowserPageOwner {
    /// Lets go of each saved or pinned tab's page the core put away as this
    /// window asked while it is open, keeping what brings it back unless the
    /// tab returned to its saved address, which drops what it kept.
    func followPutAwayPages() {
        browser.core.followPutAwayPages(self) { [weak self] in self?.pagePutAway($0) }
    }

    private func pagePutAway(_ putAway: TabPagePutAway) {
        guard browser.isOpen(as: putAway.windowID), putAway.workspaceID == browser.window.workspaceID,
            let space = browser.spaceModel(putAway.spaceID)
        else { return }
        _ = host.closeDurablePage(
            BrowserTabRuntimeAssignment(tabID: putAway.tabID, spaceID: space.id, profileID: space.profileID),
            discardState: !putAway.keepsState)
    }

    /// Hosts each page an engine opened by itself that the core adopted for a
    /// tab of this window while it is open, keeping its opener, history and
    /// script state, as the tab's resident page, whichever engine opened it.
    func followAdoptedPages() {
        browser.core.followAdoptedPages(self) { [weak self] in self?.adoptedPageOpened($0) }
    }

    private func adoptedPageOpened(_ adopted: OfferedPageAdopted) {
        guard browser.isOpen(as: adopted.windowID), adopted.workspaceID == browser.window.workspaceID,
            host.page(for: adopted.tabID) == nil,
            let space = browser.spaceModel(adopted.spaceID),
            let tab = space.tabs.model(adopted.tabID),
            let opened = browser.core.engines.host(adopted.pageID)
        else { return }
        hostAdoptedPage(
            opened, as: BrowserPageTab(tab, images: browser.core.state.favicons), in: space, shows: adopted.shows)
    }
}

// MARK: - Reconciliation

extension BrowserPageOwner {
    /// What the owner's runtime state follows in the window's workspace: tab
    /// icons, content blocking and credential access, compared between
    /// changes so each is reconciled only when it moved.
    var runtimeProjection: BrowserRuntimeSessionProjection {
        BrowserRuntimeSessionProjection(workspace: browser.workspaceModel, images: browser.core.state.favicons)
    }

    /// Releases the pages of tabs the window's workspace no longer holds and
    /// keeps the rest current.
    func reconcile() {
        host.reconcile(workspace: browser.workspaceModel, images: browser.core.state.favicons)
    }

    /// Gives every page its Space's password preference.
    func reconcileCredentialAccess() {
        host.reconcileCredentialAccess(in: browser.workspaceModel)
    }

    /// Gives each resident page its tab's current context, such as its icon.
    func reconcileTabIcons() {
        host.reconcileTabIcons(in: browser.workspaceModel, images: browser.core.state.favicons)
    }
}

// MARK: - Content blocking

extension BrowserPageOwner {
    var contentBlockingErrorDescription: String? { contentBlocking.errorDescription }

    func prepareContentBlocking() async {
        await contentBlocking.prepare()
    }

    /// Gives every page its Space's content blocking in the window's
    /// workspace, reloading presented pages only when their Space's
    /// protection level changes.
    func reconcileContentBlocking() async {
        let update = await contentBlocking.reconcile(in: browser.workspaceModel)
        let presented = presentedTabIDsAcrossWindows
        for (tabID, runtime) in host.runtimes {
            let page = runtime.page
            page.applyContentBlocking(
                policy: update.policy(for: page.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? [],
                activation: update.activation(for: page.spaceID, isPresented: presented.contains(tabID))
            )
        }
        for lease in host.liveTransientLeases {
            lease.applyContentBlocking(
                policy: update.policy(for: lease.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? []
            )
        }
    }

    /// Refreshes rule lists without reloading unchanged documents.
    func reloadContentBlocking() async {
        contentBlocking.invalidateRuleLists()
        await reconcileContentBlocking()
    }
}

// MARK: - Space data

extension BrowserPageOwner {
    /// Releases the owner's pages in the Space `space` names, then has every
    /// engine erase its profile's data.
    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        try await host.deleteData(for: space, on: browser.core, ephemeral: usesEphemeralWebsiteDataStores) {
            await releaseWindowRuntime(for: space)
            serverTrustOverrides.removeApprovals(for: space.profileID)
        }
        permissionCenter.reset(spaceID: space.spaceID)
    }

    /// Lets go of every page and download record the owner keeps for the
    /// Space `space` names. Its website data goes when every engine erases
    /// its profile.
    func releaseWindowRuntime(for space: BrowserSpaceRuntimeAssignment) async {
        guard host.spacesReleasingData.insert(space.spaceID).inserted else {
            host.nativeTabs.remove(in: space.spaceID)
            return
        }
        defer { host.spacesReleasingData.remove(space.spaceID) }
        await host.releasePages(of: space)
        downloadCenter.deleteRecords(profileID: space.profileID, spaceID: space.spaceID)
    }

    /// Lets go of everything a private workspace kept in the Spaces `spaces`
    /// names: its pages, download records, site permissions, certificate
    /// exceptions and fallback icons, and then, once the private window's
    /// own teardown finished, the website data every engine keeps in memory
    /// for their profiles, which no later private window ever uses again.
    func releasePrivateBrowsingData(in spaces: [BrowserSpaceRuntimeAssignment]) {
        host.closePrivateBrowsingSession()
        for space in spaces {
            downloadCenter.deleteRecords(profileID: space.profileID, spaceID: space.spaceID)
            permissionCenter.reset(spaceID: space.spaceID)
            serverTrustOverrides.removeApprovals(for: space.profileID)
            Task {
                await BrowserFaviconFallbackLoader.shared.removeAll(for: space.profileID)
            }
        }
        let core = browser.core
        let profileIDs = spaces.map(\.profileID)
        Task { @MainActor in
            for profileID in profileIDs {
                _ = await core.deleteData(DeleteProfileData(requestID: UUID(), profileID: profileID, ephemeral: true))
            }
        }
    }
}

// MARK: - Residency and tab state

extension BrowserPageOwner {
    /// Every page resident in the host's tabs.
    var residentPages: [BrowserPlatformPage] { host.residentPages }

    var retainedTransientPageCount: Int { host.retainedTransientPageCount }

    func containsResidentPage(for tabID: UUID) -> Bool {
        host.residentTabIDs.contains(tabID)
    }

    func containsResidentPage(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        host.residentTabIDs.contains(assignment.tabID) && host.page(matching: assignment) != nil
    }

    func siteThemeIconAccent(for tabID: UUID) -> BrowserTabIconAccent? {
        host.page(for: tabID)?.siteThemeIconAccent
    }

    func siteThemeIconAccent(matching assignment: BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? {
        host.page(matching: assignment)?.siteThemeIconAccent
    }

    func discardArchivedTabState(matching assignment: BrowserTabRuntimeAssignment) {
        host.discardArchivedTabState(matching: assignment)
    }

    func unloadPage(for tabID: UUID) {
        host.unloadPage(for: tabID)
    }

    @discardableResult
    func unloadPage(for tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        host.unloadPage(for: tabID, matching: assignment)
    }

    /// Releases a Space's resident pages without archiving them. Normal Space
    /// switching and locking preserve residency and do not call this teardown.
    func unloadPages(in spaceID: UUID) {
        host.unloadPages(in: spaceID)
    }

    func flushPendingTabStateWrites() async {
        await host.flushPendingTabStateWrites()
    }

    func pullFavicon(for tabID: UUID) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        await host.pullFavicon(for: tabID)
    }

    func pullFavicon(
        for tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        await host.pullFavicon(for: tabID, matching: assignment)
    }

    func prepareTabCopy(from source: TabState, copyID: UUID, in space: BrowserSpaceRuntimeAssignment) {
        host.prepareTabCopy(from: source, copyID: copyID, in: space)
    }

    func liveLinkURL(for assignment: BrowserTabRuntimeAssignment) -> URL? {
        host.liveLinkURL(for: assignment)
    }
}

// MARK: - Transient leases

extension BrowserPageOwner {
    /// The Peek's lease on a page for `request` in `space`, reused while the
    /// Peek asks for the same request. The Peek runs on the engine of the page
    /// it opened from: the one that staged its link, or its source tab's.
    func makePeekPageLease(
        request: BrowserPeekRequest,
        in space: SpaceModel,
        onDownloadOnlyNavigation: @escaping () -> Void
    ) -> BrowserPlatformTransientPageLease? {
        guard request.assignment == BrowserSpaceRuntimeAssignment(space: space) else { return nil }
        let opener = request.engineNavigation?.sourcePageID ?? host.page(for: request.sourceTabID)?.corePage.id
        return host.peekPageLease(for: request) {
            makeTransientPageLease(
                url: request.url, in: space, presentation: .peek, engineNavigation: request.engineNavigation,
                opener: opener, onUserActivity: {}, onDownloadOnlyNavigation: onDownloadOnlyNavigation)
        }
    }

    func retainPeekPages(for requests: [BrowserPeekRequest]) {
        host.retainPeekPages(for: requests)
    }

    func pruneTransientLeases() {
        host.pruneTransientLeases()
    }
}

// MARK: - Page commands

extension BrowserPageOwner {
    var canGoBack: Bool { activePage?.live.canGoBack == true }
    var canGoForward: Bool { activePage?.live.canGoForward == true }
    var backHistory: [BrowserNavigationHistoryItem] { activePage?.backHistory ?? [] }
    var forwardHistory: [BrowserNavigationHistoryItem] { activePage?.forwardHistory ?? [] }

    var pageZoomLabel: String {
        (activePage?.pageZoom ?? 1).pageZoomPercentage
    }

    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }

    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.actionTitle
    }

    func goBack() { activePage?.goBack() }
    func goForward() { activePage?.goForward() }
    func goBack(to item: BrowserNavigationHistoryItem) { activePage?.goToHistory(item) }
    func goForward(to item: BrowserNavigationHistoryItem) { activePage?.goToHistory(item) }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        activePage?.copyPageLinkAsMarkdown() == true
    }

    func printPage() {
        activePage?.printPage()
    }

    /// Gives every page the host keeps the new default zoom.
    func defaultPageZoomDidChange(to zoom: CGFloat) {
        host.defaultPageZoomDidChange(to: zoom)
    }
}
