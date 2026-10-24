import AppKit
import Foundation
import Observation
import os

@Observable
@MainActor
final class BrowserPagePool:
    BrowserPageOwner,
    BrowserPageHosting,
    BrowserDefaultPageZoomObserving
{

    /// How long a window a page asked for waits for its Quick Window to take
    /// its page before the page goes.
    private static let popupWindowWait: Duration = .seconds(30)
    @ObservationIgnored private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

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

    /// The focused card: the one tab the URL bar, navigation controls, find,
    /// zoom, sharing, and every lifecycle observer speak for. Split View adds
    /// cards beside it without adding a second focus.
    private(set) var activeTabID: UUID? {
        willSet {
            if let activeTabID, activeTabID != newValue,
                tabRuntimes[activeTabID]?.presentationWindowID == windowID,
                !runtimeStore.isPresented(activeTabID, outside: windowID)
            {
                activePage?.translation.suspend()
            }
        }
    }

    /// Every card the content area is presenting, in column order.
    ///
    /// Derived from the cards the core shows in this window, the same source
    /// the content area lays out, so the two can never disagree about who is
    /// on screen. A tab outside a shown split presents alone, which is one
    /// element rather than a special case, and `activeTabID` is always a
    /// member while anything is presented.
    ///
    /// Deliberately observable: a card mount reads it through
    /// `presentedPage(for:)` and has to re-render when membership changes.
    private(set) var presentedTabIDs: [UUID] = [] {
        didSet { runtimeStore.updatePresentation(of: self) }
    }
    private(set) var residencyRevision: Int {
        get { runtimeStore.revision }
        set { runtimeStore.revision = newValue }
    }
    let runtimeStore: BrowserPageRuntimeStore
    /// The window this pool hosts pages for. Its pages open through the core
    /// from this window, in its workspace.
    @ObservationIgnored let browser: BrowserStore
    var windowID: UUID { browser.windowID }
    /// Whether this pool's window is still open. A pool outlives its window
    /// while a Quick Window opened over it lasts, and the window reopened
    /// under the same identity has a pool of its own, so a pool whose window
    /// closed never registers under that identity again.
    var isWindowOpen: Bool { !browser.isClosed }
    /// The native window this pool's window is on screen as, while it is.
    @ObservationIgnored private(set) weak var presentationWindow: NSWindow?
    private(set) var isWindowFocused = true
    var publishesPageMetadataCentrally: Bool { runtimeStore.publishesPageMetadataCentrally }
    let downloadCenter: BrowserDownloadCenter
    /// Mirrors the runtime's console capture: web pages then report their
    /// calls into an installed extension to the diagnostics log.
    let permissionCenter: BrowserSitePermissionCenter

    /// Each tab owns its current and suspended configurations, including the
    /// history links that bridge ordinary pages and extension origins.
    private var tabRuntimes: [UUID: BrowserTabRuntime] {
        get { runtimeStore.runtimes }
        set { runtimeStore.runtimes = newValue }
    }
    /// The certificate exceptions every window pool of this store family
    /// shares, by profile.
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    /// The app's passkey access, refreshed as pages navigate. Nil where no
    /// composition supplied one.
    @ObservationIgnored private let passkeyAccess: BrowserPasskeyAccessController?
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let pageZoomPreferences: BrowserDefaultPageZoomStore
    @ObservationIgnored private let dialogPresenter: BrowserDialogPresenter
    /// Opens a Quick Window for a window a page asked for; the window's
    /// presentation installs it. Without one, such a page has nowhere to show
    /// and goes.
    @ObservationIgnored var popupWindowPresenter: ((BrowserQuickWindowRequest) -> Void)?
    /// Whether a Peek is open for the person rather than staged while they
    /// still drag its link; the window's transient browsing answers.
    @ObservationIgnored var isPeekOpen: (BrowserPeekRequest) -> Bool = { _ in false }
    /// Closes a Peek the window shows; the window's transient browsing does.
    @ObservationIgnored var dismissPeek: (BrowserPeekRequest) -> Void = { _ in }
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: ModifiedLinkOpener
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let handleLinkDrag: (BrowserPeekInteractionEvent) -> Void
    @ObservationIgnored private let splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored private let activateHostedNotificationSource: (UUID, UUID) -> Void
    @ObservationIgnored private let loadHTTPAuthenticationCredential: HTTPAuthenticationCredentialLoader
    @ObservationIgnored private let saveHTTPAuthenticationCredential: HTTPAuthenticationCredentialSaver
    /// Built-in content blocking, which only the WebKit engine applies.
    @ObservationIgnored let contentBlocking: BrowserContentBlockingController
    /// The pages every window over this workspace shares: tabs', leases' and
    /// the state tabs leave when their pages go.
    var host: BrowserPageHost { runtimeStore.host }

    init(
        browser: BrowserStore,
        runtimeStore: BrowserPageRuntimeStore? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore? = nil,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchEnvironment.current.usesEphemeralProfileStorage,
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloadCenter: BrowserDownloadCenter? = nil,
        passkeyAccess: BrowserPasskeyAccessController? = nil,
        loadHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialLoader = { _, _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialSaver = { _, _ in },
        tabStateArchive: (any BrowserTabStateArchiving)? = nil,
        openNewTab: @escaping (URL) -> Void = { _ in },
        openModifiedLink: @escaping ModifiedLinkOpener = { _, _, _ in nil },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        activateHostedNotificationSource:
            @escaping (UUID, UUID) -> Void = { _, _ in }
    ) {
        let dialogPresenter = BrowserDialogPresenter()
        let core = browser.core
        self.browser = browser
        self.browsingMode = browsingMode
        self.usesEphemeralWebsiteDataStores =
            usesEphemeralWebsiteDataStores || browsingMode.isPrivate
        self.pageZoomPreferences = pageZoomPreferences
        let owner =
            runtimeStore
            ?? BrowserPageRuntimeStore(
                archive: self.usesEphemeralWebsiteDataStores ? nil : tabStateArchive
            )
        self.runtimeStore = owner
        self.serverTrustOverrides = serverTrustOverrides ?? BrowserServerTrustOverrideStore()
        self.passkeyAccess = passkeyAccess
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.mediaSessionStore = browsingMode.isPrivate ? nil : mediaSessionStore
        self.dialogPresenter = dialogPresenter
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        contentBlocking = BrowserContentBlockingController(rules: core.engines.webKit?.contentRules)
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.handleLinkDrag = handleLinkDrag
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        self.activateHostedNotificationSource = activateHostedNotificationSource
        self.downloadCenter =
            downloadCenter
            ?? BrowserDownloadCenter(
                core: core,
                approveRiskyDownload: { assessment, sourceURL, spaceName, _ in
                    await dialogPresenter.approveRiskyDownload(
                        assessment: assessment,
                        sourceURL: sourceURL,
                        spaceName: spaceName
                    )
                },
                permissionCenter: permissionCenter
            )
        pageZoomPreferences.register(self)
        self.runtimeStore.register(self)
        core.engines.observeRecords(self) { [weak self] in self?.restyleVisitedLinks(after: $0) }
        core.followUnloadedPages(self) { [weak self] in self?.host.pageUnloaded($0) }
        core.followStartedDownloads(self) { [weak self] started in
            self?.host.livePages.first { $0.corePage.id == started.pageID }?.showDownloadStarted(started)
        }
        followAdoptedPages()
        followPutAwayPages()
        core.followWindowsBroughtForward(self) { [weak self] brought in
            guard let self, self.browser.isOpen(as: brought.windowID) else { return }
            bringForward()
        }
        core.followAdoptedWindows(self) { [weak self] in self?.popupWindowAdopted($0) }
        core.followClosedTransientPages(self) { [weak self] in self?.transientPageClosed($0) }
    }

    var nativeTabs: BrowserNativeTabStore { runtimeStore.nativeTabs }

    /// Every tab whose page some window over the workspace presents now.
    var presentedTabIDsAcrossWindows: Set<UUID> { runtimeStore.presentedTabIDs }

    func bindNativeWindow(_ window: NSWindow?) {
        presentationWindow = window
    }

    func setWindowFocused(_ focused: Bool) {
        isWindowFocused = focused
        if focused { runtimeStore.focus(self) }
    }

    func releaseWindowPresentation() {
        presentationWindow = nil
        activeTabID = nil
        presentedTabIDs = []
        runtimeStore.unregister(self)
    }

    func isMirroringPage(for tabID: UUID) -> Bool {
        _ = host.residentTabIDs.contains(tabID)
        guard presentedTabIDs.contains(tabID), let runtime = tabRuntimes[tabID] else { return false }
        return runtime.presentationWindowID != nil && runtime.presentationWindowID != windowID
    }

    func mirroredPageSnapshot(for tabID: UUID) -> NSImage? {
        _ = host.residentTabIDs.contains(tabID)
        return tabRuntimes[tabID]?.snapshot
    }

    func claimPresentedPage(for tabID: UUID) {
        runtimeStore.claim(tabID, for: self)
    }

    func removeTransferredPresentation(_ tabID: UUID) {
        presentedTabIDs.removeAll { $0 == tabID }
        if activeTabID == tabID { activeTabID = nil }
    }

    /// The caller commits the matching model move in the same main-actor turn.
    /// No load, teardown or archive may occur while transferring the runtime.
    func transferTabRuntime(
        from source: BrowserPagePool,
        matching assignment: BrowserTabRuntimeAssignment,
        as tab: BrowserPageTab,
        in space: SpaceModel
    ) -> Bool {
        guard canTransferTabRuntime(from: source, matching: assignment, in: space) else { return false }
        guard source.runtimeStore !== runtimeStore else { return true }
        if source.nativeTabs.contains(assignment) {
            guard source.nativeTabs.transfer(matching: assignment, to: nativeTabs) else { return false }
            source.runtimeStore.removePresentation(of: tab.id)
            return true
        }
        guard let runtime = source.tabRuntimes[tab.id] else {
            if let url = tab.url {
                let history = source.host.tabState.history(for: assignment, expecting: url)
                let state = source.host.archivedInteractionState(for: assignment, expecting: url)
                host.tabState.prepareCopy(state, url: url, history: history, for: assignment)
            }
            source.host.discardArchivedTabState(matching: assignment)
            source.runtimeStore.removePresentation(of: tab.id)
            return true
        }
        // The page keeps its engine page and moves to this window's workspace.
        guard browser.adoptPage(runtime.page.corePage, in: space.id, as: tab.id) else { return false }
        source.tabRuntimes.removeValue(forKey: tab.id)
        source.host.discardArchivedTabState(matching: assignment)
        source.runtimeStore.removePresentation(of: tab.id)
        source.residencyRevision &+= 1
        runtime.presentationWindowID = nil
        runtimeStore.install(runtime, for: tab.id, from: self)
        for page in runtime.allPages {
            page.updateNavigationContext(tab: tab)
        }
        residencyRevision &+= 1
        return true
    }

    func canTransferTabRuntime(
        from source: BrowserPagePool,
        matching assignment: BrowserTabRuntimeAssignment,
        in space: SpaceModel
    ) -> Bool {
        // The core's tear-off question already refused a Space being deleted
        // or locked, and moving the page asks the core again.
        guard assignment.spaceID == space.id, assignment.profileID == space.profileID else { return false }
        let tabID = assignment.tabID
        guard source.runtimeStore !== runtimeStore else { return true }
        guard tabRuntimes[tabID] == nil, !nativeTabs.tabIDs.contains(tabID) else { return false }
        if source.nativeTabs.tabIDs.contains(tabID) { return source.nativeTabs.contains(assignment) }
        guard let runtime = source.tabRuntimes[tabID] else { return true }
        return runtime.page.spaceID == space.id && runtime.page.profileID == space.profileID
    }

    /// Temporary windows end the lifetime of their own workspace. Normal
    /// windows only call releaseWindowPresentation and retain shared pages.
    func closeWindowWorkspace() {
        releaseWindowPresentation()
        reconcile(validTabIDs: [])
        host.releaseAllTransientPages()
    }

    func bindRuntimeRouting(_ runtime: BrowserTabRuntime, tabID: UUID) {
        for page in runtime.allPages {
            page.setPrivateBrowsing(browsingMode.isPrivate)
            page.host = self
            page.windowRouting?.pool = self
            page.downloadCenter = downloadCenter
            page.splitLinkHost = pageSplitLinkHost
            page.linkDestinationHost = linkDestinationHost
        }
    }

    func makeWindowPool(
        browser: BrowserStore,
        sharesRuntimes: Bool,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController
    ) -> BrowserPagePool {
        let owner = sharesRuntimes ? runtimeStore : BrowserPageRuntimeStore()
        owner.publishesPageMetadataCentrally = true
        let pool = BrowserPagePool(
            browser: browser, runtimeStore: owner, serverTrustOverrides: serverTrustOverrides,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            pageZoomPreferences: pageZoomPreferences,

            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter, mediaSessionStore: mediaSessionStore,
            downloadCenter: downloadCenter, passkeyAccess: passkeyAccess,
            loadHTTPAuthenticationCredential: { [weak browser] protectionSpace, spaceID in
                try await browser?.httpAuthenticationCredential(for: protectionSpace, in: spaceID)
            },
            saveHTTPAuthenticationCredential: { [weak browser] request, spaceID in
                try await browser?.saveHTTPAuthenticationCredential(
                    username: request.username, password: request.password, protectionSpace: request.protectionSpace,
                    in: spaceID, replacing: request.replacing)
            },
            openNewTab: { [weak browser] url in browser?.openNewTab(url: url) },
            openModifiedLink: { [weak browser] url, spaceID, selecting in
                browser?.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { [weak transientBrowsing] in transientBrowsing?.presentPeek($0) },
            handleLinkDrag: { [weak transientBrowsing] in transientBrowsing?.handleLinkDrag($0) },
            splitLinkHost: browser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            activateHostedNotificationSource: { [weak browser] spaceID, tabID in
                browser?.selectSpace(spaceID)
                browser?.selectTab(tabID)
            })
        browser.tabLinkProvider = pool
        browser.tabCopying = pool
        pool.setWindowFocused(false)
        return pool
    }

    var retainedTabIDs: Set<UUID> {
        _ = residencyRevision
        return Set(tabRuntimes.keys)
    }

    /// Reads an already-resident page for its own Space's chrome without
    /// selecting or loading it. Web content hosts must use presentedPage.
    func residentPage(matching assignment: BrowserTabRuntimeAssignment) -> BrowserPage? {
        guard host.residentTabIDs.contains(assignment.tabID) else { return nil }
        return host.page(matching: assignment)
    }

    /// Every page this window's host keeps, including retained transient
    /// leases. Used to answer "what is under the pointer" without recognising
    /// one engine's view class.
    var livePages: [BrowserPage] {
        _ = residencyRevision
        return host.livePages
    }

    var activePage: BrowserPage? {
        guard let activeTabID, host.residentTabIDs.contains(activeTabID) else { return nil }
        return tabRuntimes[activeTabID]?.page
    }

    /// The resident page of a presented card, or `nil` for a tab that is not
    /// on screen right now.
    ///
    /// Membership is checked rather than residency alone: a background tab can
    /// keep a resident page for as long as memory allows, and handing one to a
    /// card would put a second host on a web view that already has one.
    func presentedPage(for tabID: UUID) -> BrowserPage? {
        guard presentedTabIDs.contains(tabID), host.residentTabIDs.contains(tabID),
            let runtime = tabRuntimes[tabID],
            runtime.presentationWindowID == windowID
        else { return nil }
        return runtime.page
    }

    var hasActivePage: Bool {
        activePage?.live.documentURL != nil
    }

    /// The Peek open over the active tab, which shows in front of it. A Peek
    /// still staged by a link drag is not open yet.
    var peekPage: BrowserPage? {
        activeTabID.flatMap { host.peekPage(over: $0, where: isPeekOpen) }
    }

    /// The page the page commands act on: the Peek open over the active tab,
    /// or else the tab's own page.
    var commandPage: BrowserPage? {
        peekPage ?? activePage
    }

    /// Presents what the window shows: the tab it shows and the cards beside
    /// it, each on the page the core opens for it.
    func select(at time: Date = .now) {
        startInitialNavigations(presentCards(tab: browser.shownTab, space: browser.shownSpace, at: time))
        reconcileCredentialAccess()
    }

    /// Builds and presents the cards `tab` brings on screen without navigating
    /// any of them, answering the cards whose first load is still owed.
    private func presentCards(
        tab: TabStateModel?,
        space: SpaceModel?,
        at time: Date
    ) -> [(tab: BrowserPageTab, page: BrowserPage)] {
        let interval = Self.lifecycleSignposter.beginInterval("Select Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Select Browser Page", interval)
        }

        guard let space else {
            deactivatePagePresentation()
            return []
        }
        guard let tab else {
            leavePagePresentation()
            return []
        }
        // Every member of the selected tab's split group is a live card, so
        // each one is built and started here. A card the person can see must
        // never wait for focus to load: lazy loading is for tabs off screen.
        let members = presentedMembers(for: tab, in: space)
        // Ask the departing engine while its view is still attached. Creating
        // the destination page can hide the previous native surface first.
        requestAutomaticPictureInPicture(forDeparturesBefore: members.map(\.id))
        for member in members { nativeTabs.load(tab: member, space: space, at: time) }
        // A card the core refuses a page, such as one in a locked Space,
        // presents without one.
        let images = browser.core.state.favicons
        let memberPages = members.filter { $0.nativeContent == nil }.compactMap { member in
            let pageTab = BrowserPageTab(member, images: images)
            return page(for: pageTab, space: space).map { (tab: pageTab, page: $0) }
        }
        activate(tab.id, presenting: members.map(\.id))
        return memberPages
    }

    private func startInitialNavigations(
        _ cards: [(tab: BrowserPageTab, page: BrowserPage)]
    ) {
        for card in cards {
            loadInitialURL(for: card.tab, into: card.page)
        }
    }

    /// The split host this pool's pages open links through. The new tab's
    /// page opens and loads at once, on the engine of the page the link was
    /// followed in.
    private var pageSplitLinkHost: BrowserSplitLinkHost {
        BrowserSplitLinkHost(
            canOpenLink: splitLinkHost.canOpenLink,
            openLink: { [weak self] url, tabID, assignment in
                self?.openLinkInSplit(url, joining: tabID, matching: assignment)
            })
    }

    private func openLinkInSplit(
        _ url: URL, joining tabID: UUID, matching assignment: BrowserSpaceRuntimeAssignment
    ) -> UUID? {
        let opener = tabRuntimes[tabID]?.page.corePage.id
        guard let openedID = splitLinkHost.openLink(url, tabID, assignment) else { return nil }
        if let space = browser.spaceModel(matching: assignment), let tab = space.tabs.model(openedID) {
            let pageTab = BrowserPageTab(tab, images: browser.core.state.favicons)
            if let page = page(for: pageTab, space: space, opener: opener) { loadInitialURL(for: pageTab, into: page) }
        }
        return openedID
    }

    /// The live page of tab `tabID`, if it has one.
    func residentPage(ofTab tabID: UUID) -> BrowserPage? {
        tabRuntimes[tabID]?.page
    }

    /// The live page of `tab` in `space` for an agent the person allowed: the
    /// tab's resident page, or one made and loaded at the tab's address
    /// without this window showing it. Nil when the core refuses the tab a
    /// page.
    func agentPage(for tab: TabStateModel, in space: SpaceModel) -> BrowserPage? {
        let pageTab = BrowserPageTab(tab, images: browser.core.state.favicons)
        guard let page = page(for: pageTab, space: space) else { return nil }
        loadInitialURL(for: pageTab, into: page)
        reconcileCredentialAccess()
        return page
    }

    /// Opens the link a person followed with a modifier in page `opener` as a
    /// new tab of Space `spaceID`, whose page runs on its opener's engine.
    private func openModifiedLink(
        _ request: URLRequest,
        in spaceID: UUID,
        selecting: Bool,
        opener: UUID
    ) {
        guard let url = request.url,
            let registration = openModifiedLink(url, spaceID, selecting),
            let page = page(
                for: BrowserPageTab(registration.tab, images: browser.core.state.favicons), space: registration.space,
                opener: opener)
        else {
            return
        }
        page.load(request)
        if selecting { select() }
        reconcileCredentialAccess()
    }

    /// The cards `tab` brings on screen: the ones the core shows beside it in
    /// this window, or the tab alone when the window shows it in none.
    func presentedMembers(for tab: TabStateModel, in space: SpaceModel) -> [TabStateModel] {
        let members = browser.cards(in: space)
        return members.contains { $0.id == tab.id } ? members : [tab]
    }

    /// An unlocked empty Space or start page is an ordinary departure. Keep
    /// the same PiP lifecycle as switching between loaded tabs; security
    /// teardown uses deactivatePagePresentation instead.
    func leavePagePresentation() {
        activate(nil, presenting: [])
    }

    /// Removes every rendered page from presentation without evicting their
    /// isolated WebKit runtimes. Re-selecting the tab restores the resident
    /// page, while protected content cannot remain visible behind a lock gate.
    ///
    /// All of it goes at once, not just the focused card: a Space locking with
    /// a split open has to take every card away, and half a split left on
    /// screen would be the privacy failure the gate exists to prevent.
    func deactivatePagePresentation() {
        for runtime in tabRuntimes.values where runtime.presentationWindowID == windowID {
            runtime.page.pictureInPicture?.invalidate()
        }
        guard activeTabID != nil || !presentedTabIDs.isEmpty else { return }
        for tabID in presentedTabIDs where tabRuntimes[tabID]?.presentationWindowID == windowID {
            tabRuntimes[tabID]?.page.focusRestoration.invalidate()
        }
        activeTabID = nil
        presentedTabIDs = []
    }

    func reconcile(validTabIDs: Set<UUID>) {
        host.reconcile(validTabIDs: validTabIDs)
        if let activeTabID, !validTabIDs.contains(activeTabID) {
            self.activeTabID = nil
        }
        pruneCards(keeping: validTabIDs)
    }

    /// Drops cards for tabs that no longer exist. A split whose member was
    /// closed keeps presenting the rest; presentation is derived per selection,
    /// so a run that is no longer renderable collapses on the next one.
    private func pruneCards(keeping validTabIDs: Set<UUID>) {
        guard presentedTabIDs.contains(where: { !validTabIDs.contains($0) })
        else { return }
        presentedTabIDs = presentedTabIDs.filter { validTabIDs.contains($0) }
    }

    /// Writes out the engine session state of every resident page this window
    /// routes. The app calls this when a scene stops being active, so state
    /// survives a quit before an inactive page is unloaded.
    func archiveResidentTabStates() {
        host.archiveResidentTabStates { [windowID, publishesPageMetadataCentrally] runtime in
            runtime.routingWindowID == windowID || !publishesPageMetadataCentrally
        }
    }

    /// Lets go of everything the private workspace kept, in each of the
    /// Spaces `spaces` names, as its last window closes.
    func closePrivateBrowsingSession(_ spaces: [BrowserSpaceRuntimeAssignment]) {
        guard browsingMode.isPrivate else { return }
        releasePrivateBrowsingData(in: spaces)
    }

    /// Asks the core to load what the person typed or chose in the page the
    /// window shows. False when there is none or a rule refused it.
    @discardableResult
    func navigate(to input: String) -> Bool {
        activePage?.corePage.navigate(to: input) ?? false
    }

    /// Asks the core to load `url`, an address Crest already holds, in the
    /// page the window shows. False when there is none or a rule refused it.
    @discardableResult
    func load(_ url: URL) -> Bool {
        activePage?.corePage.load(url) ?? false
    }

    /// The cards a visited-link restyle applies to.
    ///
    /// Every presented member, not only the focused one: a link followed in one
    /// card is followed for the window, and leaving its neighbour showing the same
    /// link unstyled until that neighbour navigates for its own reasons is a lie
    /// about what has been read. The focused tab is included even in the frame
    /// where popup adoption has activated a tab the presented list has not caught
    /// up with, and pages belonging to another Space or profile are excluded — the
    /// history being applied is this Space's.
    func visitedLinkStylingTabIDs(in space: SpaceModel) -> [UUID] {
        _ = residencyRevision
        var seen: Set<UUID> = []
        return (presentedTabIDs + [activeTabID].compactMap { $0 }).filter { tabID in
            guard seen.insert(tabID).inserted, let page = tabRuntimes[tabID]?.page else {
                return false
            }
            return page.spaceID == space.id && page.profileID == space.profileID
        }
    }

    func styleVisitedLinks(in space: SpaceModel) async {
        let history = space.history.entries
        for tabID in visitedLinkStylingTabIDs(in: space) {
            await tabRuntimes[tabID]?.page.styleVisitedLinks(history: history)
        }
    }

    /// A visit the core recorded restyles every card this window shows in its
    /// Space: the card beside the one that navigated is the one most likely to
    /// show the link just followed.
    private func restyleVisitedLinks(after records: Engines.PageRecords) {
        let workspace = browser.window.workspaceID
        let spaceIDs = Set(records.navigations.filter { $0.workspaceID == workspace }.map(\.spaceID))
        for spaceID in spaceIDs {
            guard let space = browser.spaceModel(spaceID) else { continue }
            Task { @MainActor [weak self] in await self?.styleVisitedLinks(in: space) }
        }
    }

    func makeTransientPageLease(
        url: URL,
        in space: SpaceModel,
        presentation: TransientPresentation = .quickWindow,
        engineNavigation: BrowserEngineNavigation? = nil,
        opener: UUID? = nil,
        onUserActivity: @escaping () -> Void = {},
        onDownloadOnlyNavigation: (() -> Void)? = nil
    ) -> BrowserTransientPageLease? {
        host.makeTransientPageLease(
            url: url, in: space, presentation: presentation, engineNavigation: engineNavigation,
            balancedContentRuleLists: contentBlocking.balancedRuleLists ?? [], onUserActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation
        ) { [weak self] in
            self?.makePage(space: space, presentation: presentation, opener: opener)
        }
    }

    @discardableResult
    func adoptTransientPage(
        _ lease: BrowserTransientPageLease,
        as tabID: UUID,
        in space: SpaceModel
    ) -> Bool {
        // Move the renderer before Quick Window dismissal destroys its old
        // host. SwiftUI attaches the retained native view on a later update.
        // An engine that cannot move a live page between windows leaves the
        // caller to load the tab afresh instead, and so does the core when
        // the tab may not take the page.
        guard
            let page = host.adoptTransientPage(
                lease, as: tabID, in: space, through: browser,
                prepare: { [windowID] page in
                    page.pageEngine.registration.supports(.workspaceTransfer) && page.enginePage.move(to: windowID)
                })
        else { return false }
        retainResidentPage(page, for: tabID)
        residencyRevision &+= 1
        activate(tabID)
        if let tab = space.tabs.model(tabID) {
            page.updateNavigationContext(tab: BrowserPageTab(tab, images: browser.core.state.favicons))
        }
        return true
    }

    /// Lets go of a tab's page its engine closed on its own authority. The
    /// core already closed the tab as its close button would, or kept it, as
    /// a locked Space does; either way the page is gone, so nothing of it is
    /// kept, and a tab still there loads anew when shown. A Quick Window's or
    /// Peek's page goes with what shows it, which the core closes.
    func releaseEngineClosedPage(_ page: BrowserPage) {
        guard let tabID = tabID(for: page) else { return }
        host.unloadPage(for: tabID, preservingTabState: false)
    }

    // MARK: - Actions - Peek

    /// Closes the Peek open over the active tab, which Close Tab closes
    /// before the tab under it; false when no Peek is open.
    func closePeek() -> Bool {
        guard let request = activeTabID.flatMap({ host.peekRequest(over: $0, where: isPeekOpen) })
        else { return false }
        if let peekPage { returnFocus(fromPeek: peekPage) }
        dismissPeek(request)
        return true
    }

    /// Hands the keyboard back to the active tab's page as the Peek page
    /// holding it closes, as closing find hands it back to the page searched.
    /// An engine that focuses a page it shows, as Chromium does, gives the
    /// Peek the keyboard when it opens.
    func returnFocus(fromPeek peek: BrowserPage) {
        guard let page = activePage, page !== peek,
            let responder = peek.nativeView.window?.firstResponder as? NSView,
            responder.isDescendant(of: peek.nativeView)
        else { return }
        page.focusRestoration.requestPageFocus(displacing: peek.nativeView)
    }

    // MARK: - Actions - Media sessions

    /// The media session the tab's page publishes. A private window reports
    /// no media sessions.
    func mediaSession(matching assignment: BrowserTabRuntimeAssignment) -> BrowserMediaSessionSnapshot? {
        mediaSessionStore?.session(of: assignment)
    }

    /// Mutes or unmutes the sound the tab's page plays.
    func setMuted(_ muted: Bool, matching assignment: BrowserTabRuntimeAssignment) {
        mediaSessionStore?.setMuted(muted, of: assignment)
    }

    /// The engine's measure of the sound the tab's page plays, when its engine
    /// measures it.
    func audioSpectrum(matching assignment: BrowserTabRuntimeAssignment) -> BrowserAudioSpectrumFeed? {
        residentPage(matching: assignment)?.pageEngine.audioSpectrum
    }

    // MARK: - Actions - Popup windows

    /// Lets go of a popup window's page the core closed before its Quick
    /// Window took it; a Quick Window that took one closes itself.
    private func transientPageClosed(_ closed: TransientPageClosed) {
        guard closed.workspaceID == browser.window.workspaceID, let parked = host.takePopupWindowPage(closed.pageID)
        else { return }
        parked.release(keepingState: false)
    }

    /// Hosts the page the core adopted for a window a page asked for, when
    /// this pool routes that page now, and opens the Quick Window that shows
    /// it over this window, which takes the page from the host every window
    /// over the workspace shares. The page answers its navigations from now
    /// on. The core names the opener's window, but a page another window shows
    /// is routed there, and a pool left over from a window that closed under
    /// the same identity routes nothing, so neither hosts it. A page no Quick
    /// Window takes goes.
    private func popupWindowAdopted(_ adopted: OfferedWindowAdopted) {
        guard adopted.workspaceID == browser.window.workspaceID, routesPopupWindow(of: adopted) else { return }
        guard let opened = browser.core.engines.host(adopted.pageID) else { return }
        guard let space = browser.spaceModel(adopted.spaceID), let present = popupWindowPresenter,
            let url = URL(string: adopted.url),
            let page = makePage(space: space, presentation: .quickWindow, opened: opened)
        else {
            DiagnosticLog.popups.notice("No Quick Window can show popup page \(adopted.pageID) over window \(windowID)")
            opened.page.release(keepingState: false)
            return
        }
        page.markOpenedAsPopup()
        guard host.keepPopupWindowPage(page) else {
            page.release(keepingState: false)
            return
        }
        present(
            BrowserQuickWindowRequest(
                url: url, spaceAssignment: BrowserSpaceRuntimeAssignment(space: space), targetWindowID: windowID,
                openedPageID: adopted.pageID))
        Task { @MainActor [weak host] in
            try? await Task.sleep(for: Self.popupWindowWait)
            guard let page = host?.takePopupWindowPage(adopted.pageID) else { return }
            DiagnosticLog.popups.notice("No Quick Window took popup page \(adopted.pageID); it goes")
            page.release(keepingState: false)
        }
    }

    /// Whether this pool is the one to host the window `adopted` names: the
    /// pool that routes the page that asked for it now, or, when no window
    /// routes that page, the pool of the open window the core names.
    private func routesPopupWindow(of adopted: OfferedWindowAdopted) -> Bool {
        guard let source = host.livePages.first(where: { $0.corePage.id == adopted.sourcePageID }),
            let router = source.host
        else { return browser.isOpen(as: adopted.windowID) }
        return router === self
    }

    /// A lease on the page the core adopted for a popup window, `pageID`, for
    /// the Quick Window that shows it in `space`. Nil when the host keeps no
    /// such page, or it went. The page is already heading where the window
    /// asked, so the lease loads nothing; `url` is what it loads again after
    /// memory pressure.
    func makePopupWindowLease(
        for pageID: UUID, url: URL, in space: SpaceModel, onUserActivity: @escaping () -> Void
    ) -> BrowserTransientPageLease? {
        guard let page = host.takePopupWindowPage(pageID) else {
            DiagnosticLog.popups.notice("Popup page \(pageID) is gone before its Quick Window took it")
            return nil
        }
        guard page.spaceID == space.id, page.profileID == space.profileID else {
            DiagnosticLog.popups.notice("Popup page \(pageID) belongs to another Space than its Quick Window")
            page.release(keepingState: false)
            return nil
        }
        let lease = BrowserTransientPageLease(
            page: page, url: url, contentBlockingPolicy: space.settings.browsingPreferences.contentBlocking,
            balancedContentRuleLists: contentBlocking.balancedRuleLists ?? [],
            rebuild: { [weak self] in self?.makePage(space: space, presentation: .quickWindow) },
            userActivity: onUserActivity, loadsURL: false)
        host.keep(lease)
        return lease
    }

    func discardDownloadOnlyPage(_ page: BrowserPage) {
        guard !host.discardDownloadOnlyTransientPage(page) else { return }
        page.corePage.report(PageCloseRequested(pageID: page.corePage.id))
    }

    /// Brings this window and the app to the front, as the core asks when the
    /// person returns to a page from Picture in Picture. The window already
    /// shows the page's tab; selection claims its resident page and split
    /// group, and the engine returns the video inline once the page's view is
    /// back on screen. The page is never recreated or navigated here.
    private func bringForward() {
        guard let window = presentationWindow else { return }
        setWindowFocused(true)
        select()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func activateNotificationSourcePage(_ page: BrowserPage) {
        guard let tabID = tabID(for: page) else { return }
        activateHostedNotificationSource(page.spaceID, tabID)
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
        // A background Space can still remember its editor after departure.
        // Locking ends that focus session even though its pages stay resident.
        for page in host.livePages where page.spaceID == space.id {
            page.focusRestoration.invalidate()
            page.pictureInPicture?.invalidate()
        }
        if activePage?.spaceID == space.id
            || presentedTabIDs.contains(where: { tabRuntimes[$0]?.page.spaceID == space.id })
        {
            deactivatePagePresentation()
        }
        host.tabState.removeStates(profileID: space.profileID)
    }

    /// Reloads the shown tab, or brings its page back when it went.
    func reload(_ mode: BrowserPageReloadMode) {
        guard canReloadShownPage() else { return }
        activePage?.performReload(mode)
    }

    func reloadOrStop() {
        reload(.standard)
    }

    func forceReload() {
        guard canReloadShownPage() else { return }
        activePage?.reload()
    }

    func reloadFromOrigin() {
        reload(.fromOrigin)
    }

    /// Releases what memory pressure takes back that the core does not
    /// decide; see `BrowserPageHost.relieveMemoryPressure`.
    func relieveMemoryPressure(_ level: MemoryPressureLevel) {
        host.relieveMemoryPressure(level, presenting: Array(runtimeStore.presentedTabIDs))
    }

    /// Hosts `opened`, a page an engine opened by itself that the core
    /// adopted for `tab` in this window, keeping its opener, history,
    /// JavaScript state and extension tab identity, as the tab's resident
    /// page, and brings the tab forward when `shows`.
    func hostAdoptedPage(_ opened: Engines.OpenedPage, as tab: BrowserPageTab, in space: SpaceModel, shows: Bool) {
        guard let page = makePage(space: space, tabID: tab.id, opened: opened) else { return }
        page.markOpenedAsPopup()
        page.updateNavigationContext(tab: tab)
        retainResidentPage(page, for: tab.id)
        residencyRevision &+= 1
        if shows { activate(tab.id) }
    }

    /// The tab's resident page, or a new one the core opened for it, on
    /// `opener`'s engine when another page opened the tab; nil when the core
    /// refuses the tab a page.
    private func page(for tab: BrowserPageTab, space: SpaceModel, opener: UUID? = nil) -> BrowserPage? {
        if let existingPage = tabRuntimes[tab.id]?.page {
            if existingPage.spaceID == space.id,
                existingPage.profileID == space.profileID
            {
                let page = existingPage
                page.setCredentialAccessEnabled(
                    space.settings.credentialPreferences.isEnabled
                )
                page.updateNavigationContext(tab: tab)
                return page
            }
            // The tab moved to another Space, so the state archived under its old
            // profile describes a runtime it no longer belongs to.
            host.tabState.removeState(
                profileID: existingPage.profileID,
                tabID: tab.id
            )
            tabRuntimes.removeValue(forKey: tab.id)?.release(keepingState: false)
        }
        // A tab's page opens with the history its archive kept, on the engine
        // of the entry that history shows; a page another page opened keeps
        // its opener's engine instead.
        if opener == nil {
            host.restoreTabHistory(
                for: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID),
                expecting: tab.url, in: browser)
        }
        guard let page = makePage(space: space, tabID: tab.id, opener: opener) else { return nil }
        page.updateNavigationContext(tab: tab)
        retainResidentPage(page, for: tab.id)
        residencyRevision &+= 1
        return page
    }

    /// A page the core opens for `tabID` in `space`, or for a transient
    /// request presenting as `presentation`, on the engine the core chooses,
    /// which is `opener`'s when another page opened it. With `opened`, the
    /// page the core already opened for the tab instead. Nil when the core
    /// refuses it.
    private func makePage(
        space: SpaceModel,
        tabID: UUID? = nil,
        presentation: TransientPresentation? = nil,
        opener: UUID? = nil,
        opened alreadyOpened: Engines.OpenedPage? = nil
    ) -> BrowserPage? {
        let interval = Self.lifecycleSignposter.beginInterval("Create Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Create Browser Page", interval)
        }

        guard
            let opened = alreadyOpened
                ?? browser.openPage(in: space.id, for: tabID, presenting: presentation, opener: opener)
        else { return nil }
        let engine = opened.built.makeDesktopAdapter()
        let routing = BrowserPageWindowRouting(pool: self)
        let page = BrowserPage(
            corePage: opened.page,
            engine: engine,
            dialogPresenter: dialogPresenter,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            passkeyAccess: passkeyAccess,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: tabID == nil ? nil : mediaSessionStore,
            spaceID: space.id,
            profileID: space.profileID,
            spaceName: space.settings.name,
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled:
                space.settings.credentialPreferences.isEnabled,
            defaultPageZoom: pageZoomPreferences.defaultZoom,
            loadHTTPAuthenticationCredential: { [weak routing] protectionSpace in
                try await routing?.pool?.loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [weak routing] request in
                try await routing?.pool?.saveHTTPAuthenticationCredential(request, space.id)
            },
            openNewTab: { [weak routing] url in routing?.pool?.openNewTab(url) },
            openModifiedLink: { [weak routing, pageID = opened.page.id] url, spaceID, selecting in
                routing?.pool?.openModifiedLink(url, in: spaceID, selecting: selecting, opener: pageID)
            },
            openPeek: { [weak routing] in routing?.pool?.openPeek($0) },
            handleLinkDrag: { [weak routing] in routing?.pool?.handleLinkDrag($0) },
            splitLinkHost: pageSplitLinkHost,
            linkDestinationHost: linkDestinationHost
        )
        page.setPrivateBrowsing(browsingMode.isPrivate)
        page.host = self
        page.windowRouting = routing
        return page
    }

    private func tabID(for page: BrowserPage) -> UUID? {
        host.tabID(for: page)
    }

    private func retainResidentPage(_ page: BrowserPage, for tabID: UUID) {
        if let runtime = tabRuntimes[tabID] {
            runtime.page = page
        } else {
            runtimeStore.install(BrowserTabRuntime(page: page), for: tabID, from: self)
        }
    }

    private func loadInitialURL(for tab: BrowserPageTab, into page: BrowserPage) {
        // WebKit owns an adopted popup's first navigation. Loading it here would
        // replace the document `window.open()` handed to the opener.
        guard !page.isAwaitingPopupNavigation else { return }
        // A page its engine shows something in, or that is already heading
        // somewhere, has had its first navigation.
        guard page.pageEngine.currentURL == nil, page.navigationReporter?.pendingURL == nil,
            page.live.pendingURL == nil, let url = tab.url
        else { return }
        let interval = Self.lifecycleSignposter.beginInterval("Start Initial Navigation")
        // The adapter restores its own navigation state instead of a plain load.
        // Missing or incompatible archives fall back to the tab's current URL.
        if let state = host.archivedInteractionState(
            for: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: page.spaceID, profileID: page.profileID),
            expecting: url
        ), page.restoreInteractionState(state, expecting: url) {
            Self.lifecycleSignposter.endInterval("Start Initial Navigation", interval)
            return
        }
        page.corePage.load(url)
        Self.lifecycleSignposter.endInterval("Start Initial Navigation", interval)
    }

    /// Presents what the window shows, answering whether the tab it shows
    /// already had a loaded page of its Space to reload. Selection creates a
    /// missing page and starts its saved address, so that recovery never
    /// needs a second navigation.
    private func canReloadShownPage() -> Bool {
        guard let tab = browser.shownTab, let space = browser.shownSpace else { return false }
        let residentPage = tabRuntimes[tab.id]?.page
        let canReloadResidentPage =
            residentPage?.spaceID == space.id
            && residentPage?.profileID == space.profileID
            && residentPage?.live.documentURL != nil
        select()
        return canReloadResidentPage
    }

    /// Focuses a tab that is already on screen, or brings one on screen beside
    /// the cards already there.
    ///
    /// Popup adoption and extension selection reach focus without going through
    /// `select`, one frame ahead of the store-driven reselection that settles
    /// the presented set properly. Adding the tab here rather than replacing
    /// the set is what keeps that frame from rendering a card with no page.
    private func activate(_ tabID: UUID) {
        var presented = presentedTabIDs
        if !presented.contains(tabID) {
            presented.append(tabID)
        }
        activate(tabID, presenting: presented)
    }

    /// Puts `presentedTabIDs` on screen in order with `tabID` focused.
    private func activate(_ tabID: UUID?, presenting presentedTabIDs: [UUID]) {
        if tabID != activeTabID || presentedTabIDs != self.presentedTabIDs {
            let focused = tabID?.uuidString ?? "none"
            DiagnosticLog.pages.notice(
                "Window \(windowID) presents \(presentedTabIDs.map(\.uuidString)), focusing \(focused)")
            tabID.flatMap { tabRuntimes[$0]?.page }?.awaitInputSincePresented()
        }
        prepareFocusTransition(to: tabID.flatMap { tabRuntimes[$0]?.page })
        requestAutomaticPictureInPicture(forDeparturesBefore: presentedTabIDs)
        for arrivingTabID in presentedTabIDs where !self.presentedTabIDs.contains(arrivingTabID) {
            tabRuntimes[arrivingTabID]?.page.pictureInPicture?.returnToTab()
        }
        activeTabID = tabID
        self.presentedTabIDs = presentedTabIDs
    }

    private func requestAutomaticPictureInPicture(forDeparturesBefore arriving: [UUID]) {
        let departed = Set(presentedTabIDs).subtracting(arriving)
        // Only pages leaving the visible set qualify. Moving focus within a
        // split must not float a video that is still visible beside the tab.
        let departures = ([activeTabID].compactMap { $0 } + presentedTabIDs)
            .filter { departed.contains($0) }
        var requested: Set<UUID> = []
        for tabID in departures
        where requested.insert(tabID).inserted
            && !runtimeStore.isPresented(tabID, outside: windowID)
        {
            guard let pictureInPicture = tabRuntimes[tabID]?.page.pictureInPicture else { continue }
            DiagnosticLog.pages.notice(
                "Tab \(tabID) leaves window \(windowID); its video may float in Picture in Picture")
            pictureInPicture.leaveTab()
        }
    }

    private func prepareFocusTransition(to destination: BrowserPage?) {
        let source = activePage
        guard source !== destination else { return }
        if let destination, !isWindowFocused,
            let runtime = tabRuntimes.values.first(where: { $0.page === destination }),
            let owner = runtime.presentationWindowID, owner != windowID
        {
            return
        }
        guard
            activeTabID.flatMap({ tabRuntimes[$0]?.presentationWindowID }) == windowID
                || source == nil
        else { return }
        guard let source, let destination else {
            source?.focusRestoration.invalidate()
            destination?.focusRestoration.invalidate()
            return
        }

        // A click in an unfocused split card focuses the page under the
        // pointer before its selection arrives here. The destination keeps
        // that focus, and the source keeps the responder it remembers, as it
        // does when focus leaves it for nothing.
        guard !destination.focusRestoration.adoptCurrentFocus() else { return }

        // Each resident page owns its own responder. Switching Spaces does
        // not change that ownership; moving a tab or replacing its profile
        // recreates the page and invalidates the old responder separately.
        source.focusRestoration.captureBeforeDeparture()
        destination.focusRestoration.requestRestoration(
            displacing: source.nativeView
        )
    }

}
