import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileBrowserPageStore:
    BrowserPageOwner,
    BrowserDefaultPageZoomObserving
{
    typealias HTTPAuthenticationCredentialLoader =
        @MainActor (
            BrowserHTTPAuthenticationProtectionSpace,
            UUID
        ) async throws -> BrowserCredential?

    typealias HTTPAuthenticationCredentialSaver =
        @MainActor (
            BrowserHTTPAuthenticationSaveRequest,
            UUID
        ) async throws -> Void

    typealias ModifiedLinkOpener =
        @MainActor (URL, UUID, Bool) -> BrowserModifiedLinkRegistration?

    /// The focused card: the one page the toolbar, find bar, navigation
    /// controls, and every lifecycle observer speak for. Split View adds cards
    /// beside it without adding a second focus.
    private(set) var activePage: MobileBrowserPage? {
        willSet { if activePage !== newValue { activePage?.translation.suspend() } }
    }

    /// Every card the content area is presenting, in column order.
    ///
    /// Derived from the cards the core shows in this scene, the same source the
    /// content area lays out, so the two can never disagree about who is on
    /// screen. A tab outside a shown split presents alone, which is one element
    /// rather than a special case, and the active page is always a member while
    /// anything is presented.
    ///
    /// Deliberately observable: an iPad column reads it through
    /// `residentPage(matching:)` and has to re-render when membership changes.
    private(set) var presentedTabIDs: [UUID] = []
    /// The pages this window hosts: its tabs', its leases' and the state its
    /// tabs leave when their pages go.
    let host: BrowserPageHost
    var nativeTabs: BrowserNativeTabStore { host.nativeTabs }
    /// Every tab whose page this scene presents now.
    var presentedTabIDsAcrossWindows: Set<UUID> { Set(presentedTabIDs) }
    var residencyRevision: Int { host.revision }
    private(set) var urlCopyFeedbackRevision = 0
    /// What the page's feedback capsule says last, which each new revision shows.
    private(set) var pageFeedback = MobilePageFeedback.pageZoom("100%")
    private(set) var pageFeedbackRevision = 0
    let downloadCenter: BrowserDownloadCenter
    let downloadRiskConfirmation: MobileDownloadRiskConfirmationCoordinator
    /// The answers to the core's questions about this mode's downloads, which
    /// a store made on its own keeps while it lives.
    @ObservationIgnored private let downloadPrompts: BrowserDownloadPrompts
    let permissionCenter: BrowserSitePermissionCenter
    /// The certificate exceptions people accepted for this scene's pages, by
    /// profile.
    @ObservationIgnored let serverTrustOverrides = BrowserServerTrustOverrideStore()
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let openModifiedLink: ModifiedLinkOpener
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let pageZoomPreferences: BrowserDefaultPageZoomStore
    @ObservationIgnored private let loadHTTPAuthenticationCredential: HTTPAuthenticationCredentialLoader
    @ObservationIgnored private let saveHTTPAuthenticationCredential: HTTPAuthenticationCredentialSaver
    @ObservationIgnored let contentBlocking: BrowserContentBlockingController
    /// The window this store hosts pages for. Its pages open through the core
    /// from this window, in its workspace.
    @ObservationIgnored let browser: BrowserStore

    init(
        browser: BrowserStore,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchEnvironment.current.requiresIsolation,
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloads: MobileBrowserDownloads? = nil,
        loadHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialLoader = { _, _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialSaver = { _, _ in },
        tabStateArchive: (any BrowserTabStateArchiving)? = nil,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        openModifiedLink: @escaping ModifiedLinkOpener = { _, _, _ in nil },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in }
    ) {
        self.browser = browser
        self.browsingMode = browsingMode
        self.usesEphemeralWebsiteDataStores =
            usesEphemeralWebsiteDataStores || browsingMode.isPrivate
        self.pageZoomPreferences = pageZoomPreferences
        // A private store's tabs leave no state on disk, even if an archive is
        // handed in.
        host = BrowserPageHost(archive: self.usesEphemeralWebsiteDataStores ? nil : tabStateArchive)
        self.mediaSessionStore = browsingMode.isPrivate ? nil : mediaSessionStore
        self.permissionCenter = permissionCenter
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.linkDestinationHost = linkDestinationHost
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        // Windows share their browsing mode's downloads; a store made on its
        // own, such as a preview's, keeps them over its window's core.
        let downloads =
            downloads
            ?? MobileBrowserDownloads(
                core: browser.core,
                browsingMode: browsingMode,
                permissionCenter: permissionCenter
            )
        downloadRiskConfirmation = downloads.riskConfirmation
        downloadCenter = downloads.center
        downloadPrompts = downloads.prompts
        contentBlocking = BrowserContentBlockingController(rules: browser.core.engines.webKit?.contentRules)
        pageZoomPreferences.register(self)
        host.dropPresentation = { [weak self] in self?.dropPresentation(of: $0) }
        browser.core.engines.observeRecords(self) { [weak self] in self?.restyleVisitedLinks(after: $0) }
        browser.core.followUnloadedPages(self) { [weak self] in self?.host.pageUnloaded($0) }
        followAdoptedPages()
        followPutAwayPages()
    }

    /// A standard window's store: its pages' saved sign-ins, link destinations
    /// and modified clicks go through `browser`, and `transientBrowsing` shows
    /// their Peeks.
    convenience init(
        window browser: BrowserStore, usesEphemeralWebsiteDataStores: Bool,
        permissionCenter: BrowserSitePermissionCenter, mediaSessionStore: BrowserMediaSessionStore?,
        downloads: MobileBrowserDownloads?, tabStateArchive: (any BrowserTabStateArchiving)?,
        spaceAccess: BrowserSpaceAccessController, transientBrowsing: BrowserTransientBrowsingCoordinator
    ) {
        self.init(
            browser: browser, usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            permissionCenter: permissionCenter, mediaSessionStore: mediaSessionStore, downloads: downloads,
            loadHTTPAuthenticationCredential: { protectionSpace, spaceID in
                try await browser.httpAuthenticationCredential(for: protectionSpace, in: spaceID)
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                try await browser.saveHTTPAuthenticationCredential(
                    username: request.username, password: request.password,
                    protectionSpace: request.protectionSpace, in: spaceID, replacing: request.replacing)
            },
            tabStateArchive: tabStateArchive,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            openModifiedLink: { url, spaceID, selecting in
                browser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in transientBrowsing.presentPeek(request) })
    }

    var activeURL: URL? { activePage?.live.displayURL }
    var preferredContentModeActionTitle: LocalizedStringResource {
        activePage?.isRequestingDesktopSite == true
            ? "Request Mobile Website"
            : "Request Desktop Website"
    }
    var residentPageCount: Int { host.runtimes.count }

    /// Which tab of the workspace belongs to which Space and profile, which
    /// page residency follows.
    var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment> {
        Set(
            browser.spaceModels.flatMap { space in
                space.tabs.models.map {
                    BrowserTabRuntimeAssignment(tabID: $0.id, spaceID: space.id, profileID: space.profileID)
                }
            })
    }

    /// Presents what the scene shows.
    func select(at time: Date = .now) {
        if !prepareSelectedPage(at: time) {
            deactivatePagePresentation()
        }
        reconcileCredentialAccess()
    }

    /// Presents what the scene shows and asks the core to load what the
    /// person typed or chose in its page, instead of the tab's own address.
    /// False when there is no page or a rule refused the load.
    @discardableResult
    func selectAndNavigate(to input: String, at time: Date = .now) -> Bool {
        defer { reconcileCredentialAccess() }
        guard prepareSelectedPage(at: time, loadsInitialURL: false) else {
            deactivatePagePresentation()
            return false
        }
        return activePage?.corePage.navigate(to: input) ?? false
    }

    /// Starts the original request in its newly registered tab, independently
    /// of whether the shared focus policy selects it, on the engine of page
    /// `opener`, which followed the link.
    func loadOpenedLink(
        _ registration: BrowserModifiedLinkRegistration, request: URLRequest, selecting: Bool, opener: UUID
    ) {
        let space = registration.space
        guard registration.tab.nativeContent == nil,
            let page = makeResidentPage(
                for: BrowserPageTab(registration.tab, images: browser.core.state.favicons), in: space,
                loadsInitialURL: false, opener: opener)
        else { return }
        host.retain(page, for: registration.tab.id)
        page.load(request)
        if selecting { select() }
    }

    private func prepareSelectedPage(at time: Date, loadsInitialURL: Bool = true) -> Bool {
        guard let space = browser.shownSpace,
            let tab = browser.shownTab
        else {
            return false
        }
        // Unlike macOS, only the focused member is built here. A phone shows
        // one card at a time and asks `prepareResidentPage(for:)` for the
        // cards either side, which is what keeps a four-member group to
        // focused ±1 live web views on a phone.
        let presented = presentedMemberIDs(for: tab, in: space)
        if tab.nativeContent != nil {
            nativeTabs.load(tab: tab, space: space, at: time)
            deactivatePagePresentation()
            presentedTabIDs = presented
            return true
        }
        let pageTab = BrowserPageTab(tab, images: browser.core.state.favicons)
        if let existing = host.page(
            matching: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID))
        {
            existing.setCredentialAccessEnabled(space.settings.credentialPreferences.isEnabled)
            existing.updateNavigationContext(tab: pageTab)
            activate(existing, presenting: presented)
            return true
        }
        releaseMismatchedPage(of: tab.id)

        // The core refuses a page in a locked Space or one being deleted.
        guard let page = makeResidentPage(for: pageTab, in: space, loadsInitialURL: loadsInitialURL) else {
            return false
        }
        host.retain(page, for: tab.id)
        activate(page, presenting: presented)
        return true
    }

    /// Lets go of the page a tab kept in another Space: the state archived
    /// under its old profile describes a runtime it no longer belongs to.
    private func releaseMismatchedPage(of tabID: UUID) {
        guard let mismatched = host.runtimes.removeValue(forKey: tabID) else { return }
        host.tabState.removeState(profileID: mismatched.page.profileID, tabID: tabID)
        mismatched.release(keepingState: false)
        host.revision &+= 1
    }

    /// The cards `tab` brings on screen: the ones the core shows beside it in
    /// this scene, or the tab alone when the scene shows it in none.
    private func presentedMemberIDs(for tab: TabStateModel, in space: SpaceModel) -> [UUID] {
        let members = browser.cards(in: space).map(\.id)
        return members.contains(tab.id) ? members : [tab.id]
    }

    /// Builds a resident page for a presented card that is not the focused one.
    ///
    /// Same guards as the selected-page path minus the activation: the card is
    /// on screen, so its page must start loading immediately, but focus stays
    /// where the session put it. Answers the page a card can bind, or `nil` when
    /// the tab is not a live member of the selected Space right now.
    @discardableResult
    func prepareResidentPage(for tabID: UUID, at time: Date = .now) -> MobileBrowserPage? {
        guard let space = browser.shownSpace,
            let tab = space.tabs.model(tabID)
        else { return nil }

        if tab.nativeContent != nil {
            nativeTabs.load(tab: tab, space: space, at: time)
            return nil
        }
        let pageTab = BrowserPageTab(tab, images: browser.core.state.favicons)
        if let existing = host.page(
            matching: BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
        {
            existing.setCredentialAccessEnabled(space.settings.credentialPreferences.isEnabled)
            existing.updateNavigationContext(tab: pageTab)
            return existing
        }
        releaseMismatchedPage(of: tabID)

        guard let page = makeResidentPage(for: pageTab, in: space) else { return nil }
        host.retain(page, for: tabID)
        return page
    }

    /// The resident page of a presented card, once its Space and profile are
    /// confirmed to be the ones the caller is drawing.
    ///
    /// A card binds a page it did not select, so the drift the selected-page port
    /// guards against is a live risk here too: a Space switch or a profile
    /// rebuild can leave a cell holding a stale assignment for one frame, and
    /// binding a page across that boundary is exactly the isolation failure
    /// per-Space browsing exists to prevent.
    ///
    /// Membership is checked rather than residency alone: a background tab can
    /// keep a resident page for as long as memory allows, and handing one to a
    /// card would put a second host on a web view that already has one.
    func residentPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> MobileBrowserPage? {
        _ = residencyRevision
        guard presentedTabIDs.contains(assignment.tabID) else { return nil }
        return host.page(matching: assignment)
    }

    /// The page a tab of the shown Space keeps in memory, for the address
    /// bar's swipe to slide in, or nil when it keeps none. Never builds one:
    /// touching the bar does not load a tab.
    ///
    /// On a phone only the shown tab's page is ever on screen, so the swipe's
    /// is the one host it gets while the swipe moves.
    func swipePreviewPage(for tabID: UUID) -> MobileBrowserPage? {
        _ = residencyRevision
        guard let space = browser.shownSpace else { return nil }
        return host.page(
            matching: BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
    }

    /// Removes every rendered page from presentation without evicting their
    /// isolated WebKit runtimes. Selecting that tab again can reuse the resident
    /// page, but no previous Space can remain visible underneath the tab viewer
    /// or a private-Space lock transition.
    ///
    /// All of it goes at once, not just the focused card: a Space locking with a
    /// split open has to take every card away, and half a split left on screen
    /// would be the privacy failure the gate exists to prevent.
    func deactivatePagePresentation() {
        guard activePage != nil || !presentedTabIDs.isEmpty else { return }
        presentedTabIDs = []
        self.activePage = nil
    }

    /// Takes a tab's card off screen once its page or native content went.
    private func dropPresentation(of tabID: UUID) {
        if activePage?.tabID == tabID { activePage = nil }
        if presentedTabIDs.contains(tabID) { presentedTabIDs.removeAll { $0 == tabID } }
    }

    func reconcile(validTabIDs: Set<UUID>) {
        host.reconcile(validTabIDs: validTabIDs)
        if let activePage, !validTabIDs.contains(activePage.tabID) {
            self.activePage = nil
        }
        // A card whose tab is gone must stop being a card in the same pass, or
        // a column would stay for a member the session no longer has.
        if presentedTabIDs.contains(where: { !validTabIDs.contains($0) }) {
            presentedTabIDs = presentedTabIDs.filter { validTabIDs.contains($0) }
        }
    }

    /// The media session the tab's page publishes. A private window reports
    /// no media sessions.
    func mediaSession(matching assignment: BrowserTabRuntimeAssignment) -> BrowserMediaSessionSnapshot? {
        mediaSessionStore?.session(of: assignment)
    }

    /// Mutes or unmutes the sound the tab's page plays.
    func setMuted(_ muted: Bool, matching assignment: BrowserTabRuntimeAssignment) {
        mediaSessionStore?.setMuted(muted, of: assignment)
    }

    /// Lets go of everything the private workspace kept, in each of the
    /// Spaces `spaces` names, as its scene closes.
    func closePrivateBrowsingSession(_ spaces: [BrowserSpaceRuntimeAssignment]) {
        guard browsingMode.isPrivate else { return }
        activePage = nil
        presentedTabIDs = []
        releasePrivateBrowsingData(in: spaces)
    }

    func styleVisitedLinks(in space: SpaceModel) async {
        await activePage?.styleVisitedLinks(history: space.history.entries)
    }

    /// A visit the core recorded in the Space the active page shows restyles
    /// its visited links.
    private func restyleVisitedLinks(after records: Engines.PageRecords) {
        guard let page = activePage,
            records.navigations.contains(where: {
                $0.workspaceID == browser.window.workspaceID && $0.spaceID == page.spaceID
            }),
            let space = browser.spaceModel(page.spaceID)
        else { return }
        Task { @MainActor [weak self] in await self?.styleVisitedLinks(in: space) }
    }

    func makeTransientPageLease(
        url: URL,
        in space: SpaceModel,
        presentation: TransientPresentation = .quickWindow,
        engineNavigation: BrowserEngineNavigation? = nil,
        opener: UUID? = nil,
        onUserActivity: @escaping () -> Void = {},
        onDownloadOnlyNavigation: (() -> Void)? = nil
    ) -> MobileBrowserTransientPageLease? {
        let transientTab = BrowserPageTab.transient(showing: url)
        return host.makeTransientPageLease(
            url: url, in: space, presentation: presentation, engineNavigation: engineNavigation,
            balancedContentRuleLists: contentBlocking.balancedRuleLists ?? [], onUserActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation
        ) { [weak self] in
            self?.makeTransientPage(tab: transientTab, in: space, presenting: presentation, opener: opener)
        }
    }

    /// Opens a transient request's page through the core, presenting as
    /// `presentation`, on `opener`'s engine when another page opened it;
    /// `tab` is the request's own stand-in, which no Space holds. Nil when
    /// the core refuses it.
    private func makeTransientPage(
        tab: BrowserPageTab,
        in space: SpaceModel,
        presenting presentation: TransientPresentation,
        opener: UUID?
    ) -> MobileBrowserPage? {
        guard let opening = browser.openPage(in: space.id, for: nil, presenting: presentation, opener: opener) else {
            return nil
        }
        return host(
            MobileBrowserPage(
                corePage: opening.page,
                webKitPage: webKitPage(opening),
                tab: tab,
                space: space,
                downloadCenter: downloadCenter,
                permissionCenter: permissionCenter,
                serverTrustOverrides: serverTrustOverrides,
                allowsCredentialAccess: !browsingMode.isPrivate,
                isCredentialAccessEnabled: space.settings.credentialPreferences.isEnabled,
                defaultPageZoom: pageZoomPreferences.defaultZoom,
                loadsInitialURL: false,
                loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                    try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
                },
                saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                    try await saveHTTPAuthenticationCredential(request, space.id)
                },
                linkDestinationHost: linkDestinationHost,
                openModifiedLink: openModifiedLink,
                openPeek: openPeek
            ))
    }

    /// What WebKit's binding built for a page the core opened.
    private func webKitPage(_ opening: Engines.OpenedPage) -> WebKitEnginePage {
        guard let page = opening.built as? WebKitEnginePage else {
            preconditionFailure("WebKit built something other than its page.")
        }
        return page
    }

    /// A page the core opened, now hosted by this store.
    private func host(_ page: MobileBrowserPage) -> MobileBrowserPage {
        page.host = self
        return page
    }

    @discardableResult
    func adoptTransientPage(
        _ lease: MobileBrowserTransientPageLease,
        as tabID: UUID,
        in space: SpaceModel
    ) -> Bool {
        guard let tab = space.tabs.model(tabID),
            let page = host.adoptTransientPage(lease, as: tabID, in: space, through: browser, prepare: { _ in true })
        else { return false }
        page.adopt(tabID: tabID, tab: BrowserPageTab(tab, images: browser.core.state.favicons))
        host.retain(page, for: tabID)
        activate(page)
        return true
    }

    /// Retires an empty surface whose initial navigation became a download:
    /// a transient one closes, and a tab's page asks the core to close it as
    /// its own script would.
    func discardDownloadOnlyPage(_ page: MobileBrowserPage) {
        guard !host.discardDownloadOnlyTransientPage(page) else { return }
        page.corePage.report(PageCloseRequested(pageID: page.corePage.id))
    }

    /// Hides a protected Space without unloading its tabs. Unlocking can reuse
    /// the same WebKit pages, including scroll position and unsaved form state.
    /// Resident pages remain subject to normal idle and memory-pressure limits.
    ///
    /// Previously archived state is still purged from disk. This preserves only
    /// live pages, not a disk snapshot of a protected Space. The access views
    /// gate ordinary and transient content until authentication succeeds.
    func relockProtectedSpace(_ space: SpaceModel) {
        guard space.settings.requiresAuthentication else { return }
        if activePage?.spaceID == space.id
            || presentedTabIDs.contains(where: { host.page(for: $0)?.spaceID == space.id })
        {
            deactivatePagePresentation()
        }
        host.tabState.removeStates(profileID: space.profileID)
    }

    func reloadOrStop() {
        activePage?.reloadOrStop()
    }

    func reload() {
        activePage?.reload()
    }

    func reloadFromOrigin() {
        activePage?.performReload(.fromOrigin)
    }

    func togglePreferredContentMode() {
        activePage?.togglePreferredContentMode()
    }

    func zoomIn() {
        guard activePage?.zoomIn() == true else { return }
        showFeedback(.pageZoom(pageZoomLabel))
    }

    func zoomOut() {
        guard activePage?.zoomOut() == true else { return }
        showFeedback(.pageZoom(pageZoomLabel))
    }

    func resetZoom() {
        guard activePage?.resetZoom() == true else { return }
        showFeedback(.pageZoom(pageZoomLabel))
    }

    /// Shows `feedback` in the page's capsule.
    func showFeedback(_ feedback: MobilePageFeedback) {
        pageFeedback = feedback
        pageFeedbackRevision &+= 1
    }

    @discardableResult
    func copyPageLink() -> Bool {
        guard activePage?.copyPageLink() == true else { return false }
        urlCopyFeedbackRevision &+= 1
        return true
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportPDF(to: destination)
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportWebArchive(to: destination)
    }

    func cancelDownload(_ itemID: UUID) {
        downloadCenter.cancel(itemID)
    }

    func clearDownload(_ itemID: UUID) {
        downloadCenter.clear(itemID)
    }

    func exportDownload(
        _ itemID: UUID,
        to destination: MobileBrowserFileExportDestination
    ) {
        guard let item = downloadCenter.item(itemID),
            item.phase.isComplete,
            let destinationURL = item.destinationURL
        else { return }
        MobileBrowserDialogPresenter.exportDownloadedFile(
            at: destinationURL,
            to: destination
        )
    }

    /// Opens a page for `tab` in `space` through the core and hosts what WebKit
    /// built, on `opener`'s engine when another page opened the tab; nil when
    /// the core refuses the tab a page.
    private func makeResidentPage(
        for tab: BrowserPageTab,
        in space: SpaceModel,
        loadsInitialURL: Bool = true,
        opener: UUID? = nil
    ) -> MobileBrowserPage? {
        if opener == nil {
            host.restoreTabHistory(
                for: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                expecting: tab.url, in: browser)
        }
        guard let opening = browser.openPage(in: space.id, for: tab.id, opener: opener) else { return nil }
        // A page the core brings back shows itself heading to what it kept,
        // and restores that in place of its first load.
        let loadsInitialURL = loadsInitialURL && opening.page.live.pendingURL == nil
        // Restoring WebKit's session state performs its own navigation, so the
        // page must not also start the tab's URL: whichever path runs, exactly one
        // navigation begins. Read only once the core opened the page, so a
        // refused page leaves the archive as it was.
        let archivedState =
            loadsInitialURL
            ? tab.url.flatMap {
                host.archivedInteractionState(
                    for: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                    expecting: $0)
            }
            : nil
        let page = residentPage(hosting: opening, for: tab, in: space)
        // Anything WebKit will not take falls through to the plain load the page
        // would otherwise start, which the core asks its engine for.
        if loadsInitialURL, let url = tab.url,
            archivedState.map({ !page.restoreInteractionState($0, expecting: url) }) ?? true
        {
            page.corePage.load(url)
        }
        return page
    }

    /// Hosts `opening`, a page the core opened for `tab` in `space`, as the
    /// page of a tab, which loads nothing until the core asks it to.
    private func residentPage(
        hosting opening: Engines.OpenedPage, for tab: BrowserPageTab, in space: SpaceModel
    ) -> MobileBrowserPage {
        host(
            MobileBrowserPage(
                corePage: opening.page,
                webKitPage: webKitPage(opening),
                tab: tab,
                space: space,
                downloadCenter: downloadCenter,
                permissionCenter: permissionCenter,
                serverTrustOverrides: serverTrustOverrides,
                mediaSessionStore: mediaSessionStore,
                allowsCredentialAccess: !browsingMode.isPrivate,
                isCredentialAccessEnabled: space.settings.credentialPreferences.isEnabled,
                defaultPageZoom: pageZoomPreferences.defaultZoom,
                // The core loads the tab's address once the page is open.
                loadsInitialURL: false,
                loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                    try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
                },
                saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                    try await saveHTTPAuthenticationCredential(request, space.id)
                },
                linkDestinationHost: linkDestinationHost,
                openModifiedLink: openModifiedLink,
                openPeek: openPeek
            ))
    }

    /// Hosts `opened`, a page an engine opened by itself that the core
    /// adopted for `tab` in this scene, as the tab's resident page, and
    /// brings the tab forward when `shows`.
    func hostAdoptedPage(_ opened: Engines.OpenedPage, as tab: BrowserPageTab, in space: SpaceModel, shows: Bool) {
        let page = residentPage(hosting: opened, for: tab, in: space)
        page.markOpenedAsPopup()
        host.retain(page, for: tab.id)
        if shows { activate(page) }
    }

    /// Focuses a page that is already on screen, or brings one on screen beside
    /// the cards already there.
    ///
    /// Popup adoption and extension selection reach focus without going through
    /// `select`, one frame ahead of the store-driven reselection that settles the
    /// presented set properly. Adding the tab here rather than replacing the set
    /// is what keeps that frame from rendering a card with no page.
    private func activate(_ page: MobileBrowserPage) {
        var presented = presentedTabIDs
        if !presented.contains(page.tabID) {
            presented.append(page.tabID)
        }
        activate(page, presenting: presented)
    }

    /// Puts `presented` on screen in order with `page` focused.
    private func activate(_ page: MobileBrowserPage, presenting presented: [UUID]) {
        // Guarded: `select` runs on every selection synchronization, and an
        // unconditional write would remount a card's host on changes that left
        // membership exactly as it was.
        if presentedTabIDs != presented {
            presentedTabIDs = presented
        }
        activePage = page
    }

    /// Writes out the WebKit session state of every resident page. The app calls
    /// this when a scene stops being active, so state survives a termination
    /// before an inactive page is unloaded.
    func archiveResidentTabStates() {
        host.archiveResidentTabStates()
    }
}
