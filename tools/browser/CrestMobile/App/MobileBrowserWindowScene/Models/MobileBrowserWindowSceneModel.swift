import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserWindowSceneModel {
    // MARK: - Types

    /// A window's private browsing: a private workspace of its own and what
    /// shows it. It closes with the window.
    struct PrivateBrowsingRuntime {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let navigation: MobileBrowserNavigationState
        let transientBrowsing: BrowserTransientBrowsingCoordinator
    }

    // MARK: - Variables

    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    /// This window's private browsing. A window shown again after it closed
    /// browses in a new private workspace, never in the one that closed.
    private(set) var privateRuntime: PrivateBrowsingRuntime
    let windowState: BrowserWindowStateStore
    let pageStoreRegistry: MobileBrowserPageStoreRegistry
    let spaceAccess: BrowserSpaceAccessController
    let startupBehavior: StartupBehavior

    @ObservationIgnored private let privateDownloads: MobileBrowserDownloads?
    /// Whether the window closed, taking its private workspace with it.
    @ObservationIgnored private var isClosed = false

    var privateBrowser: BrowserStore { privateRuntime.browser }
    var privatePages: MobileBrowserPageStore { privateRuntime.pages }
    var privateNavigation: MobileBrowserNavigationState { privateRuntime.navigation }
    var privateTransientBrowsing: BrowserTransientBrowsingCoordinator { privateRuntime.transientBrowsing }

    // MARK: - Initializers

    init(
        id: UUID,
        rootBrowser: BrowserStore,
        permissionCenter: BrowserSitePermissionCenter,
        pageStoreRegistry: MobileBrowserPageStoreRegistry,
        spaceAccess: BrowserSpaceAccessController,
        tabStateArchive: (any BrowserTabStateArchiving)?,
        windowLayouts: BrowserWindowLayouts,
        startupBehavior: StartupBehavior,
        monitorsMemoryPressure: Bool,
        usesEphemeralWebsiteDataStores: Bool = false,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloads: MobileBrowserDownloads? = nil,
        privateDownloads: MobileBrowserDownloads? = nil
    ) {
        // A scene restores the Space it showed and starts without a tab.
        let browser = rootBrowser.makeWindowStore(BrowserWindowOpening(id: id, saved: true, restoresTabs: false))
        let windowState = BrowserWindowStateStore(id: id, browser: browser, layouts: windowLayouts)
        let sidebarIsPresented = windowState.sidebarIsPresented ?? true
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            initiallyShowsCompactPage: !sidebarIsPresented,
            allowsCompactFloatingSidebar: MobileBrowserRootPreferences.allowsFloatingSidebar
        )
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let pages = MobileBrowserPageStore(
            browser: browser,
            // The window's own store is where a tab's web view actually lives, so
            // this is the residency a squeeze has to reach.
            monitorsMemoryPressure: monitorsMemoryPressure,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessionStore,
            downloads: downloads,
            loadHTTPAuthenticationCredential: { protectionSpace, spaceID in
                try await browser.httpAuthenticationCredential(
                    for: protectionSpace,
                    in: spaceID
                )
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                try await browser.saveHTTPAuthenticationCredential(
                    username: request.username,
                    password: request.password,
                    protectionSpace: request.protectionSpace,
                    in: spaceID,
                    replacing: request.replacing
                )
            },
            tabStateArchive: tabStateArchive,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            openNewTab: { url in browser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                browser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in transientBrowsing.presentPeek(request) }
        )
        browser.tabLinkProvider = pages
        browser.tabCopying = pages
        self.browser = browser
        self.navigation = navigation
        self.pages = pages
        self.transientBrowsing = transientBrowsing
        privateRuntime = Self.openPrivateBrowsing(
            core: rootBrowser.core, sidebarIsPresented: sidebarIsPresented, spaceAccess: spaceAccess,
            downloads: privateDownloads)
        self.privateDownloads = privateDownloads
        self.windowState = windowState
        self.pageStoreRegistry = pageStoreRegistry
        self.spaceAccess = spaceAccess
        self.startupBehavior = startupBehavior
    }

    // MARK: - Actions - Window

    @discardableResult
    func presentGettingStartedAfterSetup(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                accessController: spaceAccess),
            browser.spaceModels.first?.id == space.id,
            browser.selectedTabID(in: space.id) == assignment.tabID,
            space.tabs.model(assignment.tabID)?.nativeTabContent == .gettingStarted
        else { return false }
        pages.select()
        navigation.presentSelectedTabAfterSetup()
        return true
    }

    func activateWindow() {
        reopenIfClosed()
        pageStoreRegistry.register(pages)
    }

    func cleanupDeferredWebsiteDataStores() async {
        await BrowserDeferredWebsiteDataStoreCleanup.cleanupPendingStores()
    }

    func sweepExpiredTabsWhileActive() async {
        await browser.sweepExpiredBrowsingDataWhileSceneIsActive {
            pages.downloadCenter.sweepExpiredRecords(in: browser.spaceModels)
        }
    }

    func handleMemoryPressure() {
        pages.handleMemoryPressure(.critical)
        privatePages.handleMemoryPressure(.critical)
    }

    func prepareForInactiveScene() {
        spaceAccess.lockAllForInactiveScene()
        flushPendingPersistence()
    }

    func prepareForBackgroundScene() {
        spaceAccess.lockAll()
        flushPendingPersistence()
    }

    /// The window closed. Other windows still present the standard
    /// confirmations they share; this window's private workspace closes with
    /// it, and so do its private downloads and their records in the shared
    /// private center. Closing it again does nothing.
    func closeWindowRuntime() {
        guard !isClosed else { return }
        isClosed = true
        closePrivateWorkspace()
        pageStoreRegistry.unregister(pages)
        flushPendingPersistence()
    }

    func togglePrivateBrowsing(from mode: BrowserBrowsingMode) -> BrowserBrowsingMode {
        if mode.isPrivate {
            cancelPrivateDownloadConfirmations()
            synchronizeSidebarPresentation(navigation)
            return .standard
        }

        synchronizeSidebarPresentation(privateNavigation)
        privateNavigation.selectTab()
        return .privateBrowsing
    }

    func closePrivateBrowsing() -> BrowserBrowsingMode {
        let closingSpaces = privateBrowser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:))
        cancelPrivateDownloadConfirmations()
        privatePages.closePrivateBrowsingSession(closingSpaces)
        privateBrowser.resetPrivateBrowsingSession()
        privateNavigation.showTabViewer()
        privateTransientBrowsing.dismissPeek()
        synchronizeSidebarPresentation(navigation)
        return .standard
    }

    /// Opens a link another app handed this window where the core routes it,
    /// which is never a locked Space.
    @discardableResult
    func routeExternalURL(_ url: URL) async -> Bool {
        guard ExternalWebLink.accepts(url),
            let placement = try? browser.core.query(
                RouteExternalLink(windowIDs: [browser.windowID], url: url.absoluteString)),
            let spaceID = placement.spaceID,
            let space = browser.spaceModel(spaceID),
            await spaceAccess.unlock(space)
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.spaceModel(matching: assignment) != nil else { return false }
        if placement.opensQuickWindow {
            transientBrowsing.presentQuickWindow(BrowserQuickWindowRequest(url: url, spaceAssignment: assignment))
            return true
        }
        guard browser.openNewTab(url: url, matching: assignment) != nil else { return false }
        pages.selectAndNavigate(to: url.absoluteString)
        navigation.selectTab()
        return true
    }

    // MARK: - Actions - Private browsing

    /// A new private workspace in `core` and what shows it in this window.
    private static func openPrivateBrowsing(
        core: CrestCore, sidebarIsPresented: Bool, spaceAccess: BrowserSpaceAccessController,
        downloads: MobileBrowserDownloads?
    ) -> PrivateBrowsingRuntime {
        let privateBrowser = BrowserStore.privateBrowsing(core: core)
        let privateNavigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            allowsCompactFloatingSidebar: MobileBrowserRootPreferences.allowsFloatingSidebar
        )
        let privateTransientBrowsing = BrowserTransientBrowsingCoordinator()
        let privatePages = MobileBrowserPageStore(
            browser: privateBrowser,
            browsingMode: .privateBrowsing,
            permissionCenter: downloads?.center.permissionCenter ?? BrowserSitePermissionCenter(),
            downloads: downloads,
            linkDestinationHost: BrowserLinkDestinationHost(browser: privateBrowser, spaceAccess: spaceAccess),
            openNewTab: { url in privateBrowser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                privateBrowser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in
                privateTransientBrowsing.presentPeek(request)
            }
        )

        privateBrowser.tabLinkProvider = privatePages
        privateBrowser.tabCopying = privatePages
        return PrivateBrowsingRuntime(
            browser: privateBrowser, pages: privatePages, navigation: privateNavigation,
            transientBrowsing: privateTransientBrowsing)
    }

    /// Closes this window's private workspace, once: its pages, downloads and
    /// their records go with it.
    private func closePrivateWorkspace() {
        cancelPrivateDownloadConfirmations()
        for space in privateBrowser.spaceModels {
            privatePages.downloadCenter.deleteRecords(profileID: space.profileID, spaceID: space.id)
        }
        privateBrowser.close()
        privateBrowser.family.close()
    }

    /// A window shown again after it closed browses privately in a new
    /// workspace.
    private func reopenIfClosed() {
        guard isClosed else { return }
        isClosed = false
        privateRuntime = Self.openPrivateBrowsing(
            core: browser.core, sidebarIsPresented: windowState.sidebarIsPresented ?? true, spaceAccess: spaceAccess,
            downloads: privateDownloads)
    }

    /// Private downloads share one confirmation across windows; this window
    /// cancels only its own private profile's requests.
    private func cancelPrivateDownloadConfirmations() {
        privatePages.downloadRiskConfirmation.cancelAll(
            profileIDs: Set(privateBrowser.spaceModels.map(\.profileID)))
    }

    private func flushPendingPersistence() {
        // Reading resident WebKit session state must happen while pages remain
        // resident, before the asynchronous persistence flush begins.
        pages.archiveResidentTabStates()
        // iOS may suspend the app once the scene leaves the foreground and end
        // it while suspended, so the flush keeps it running until it is done.
        let backgroundTask = MobileBackgroundTask(named: "Save pending edits")
        Task { [browser, pages] in
            await BrowserPersistenceFlush().run {
                await browser.flushPendingSyncPersistenceUntilSettled()
                await pages.flushPendingTabStateWrites()
            }
            backgroundTask.end()
        }
    }

    private func synchronizeSidebarPresentation(
        _ navigation: MobileBrowserNavigationState
    ) {
        if windowState.sidebarIsPresented ?? true {
            navigation.dockRegularSidebar()
            return
        }
        navigation.hideRegularSidebar()
    }
}
