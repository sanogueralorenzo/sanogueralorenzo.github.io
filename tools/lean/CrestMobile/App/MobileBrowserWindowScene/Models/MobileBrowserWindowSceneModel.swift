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
    }

    // MARK: - Variables

    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    /// This window's private browsing. A window shown again after it closed
    /// browses in a new private workspace, never in the one that closed.
    private(set) var privateRuntime: PrivateBrowsingRuntime
    let windowState: BrowserWindowStateStore
    let pageStoreRegistry: MobileBrowserPageStoreRegistry

    @ObservationIgnored private let privateDownloads: MobileBrowserDownloads?
    /// Whether the window closed, taking its private workspace with it.
    @ObservationIgnored private var isClosed = false

    var privateBrowser: BrowserStore { privateRuntime.browser }
    var privatePages: MobileBrowserPageStore { privateRuntime.pages }
    var privateNavigation: MobileBrowserNavigationState { privateRuntime.navigation }

    // MARK: - Initializers

    init(
        id: UUID,
        rootBrowser: BrowserStore,
        permissionCenter: BrowserSitePermissionCenter,
        pageStoreRegistry: MobileBrowserPageStoreRegistry,
        tabStateArchive: (any BrowserTabStateArchiving)?,
        windowLayouts: BrowserWindowLayouts,
        usesEphemeralWebsiteDataStores: Bool = false,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloads: MobileBrowserDownloads? = nil,
        privateDownloads: MobileBrowserDownloads? = nil
    ) {
        // A scene restores the Space and tab it last showed.
        let browser = rootBrowser.makeWindowStore(BrowserWindowOpening(id: id, saved: true, restoresTabs: true))
        let windowState = BrowserWindowStateStore(id: id, browser: browser, layouts: windowLayouts)
        let sidebarIsPresented = windowState.sidebarIsPresented ?? true
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            initiallyShowsCompactPage: browser.shownTab != nil,
            allowsCompactFloatingSidebar: MobileBrowserRootPreferences.allowsFloatingSidebar
        )
        let pages = MobileBrowserPageStore(
            browser: browser, usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessionStore,
            downloads: downloads,
            tabStateArchive: tabStateArchive,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser),
            openModifiedLink: { url, spaceID, selecting in
                browser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
        )
        browser.tabLinkProvider = pages
        browser.tabCopying = pages
        self.browser = browser
        self.navigation = navigation
        self.pages = pages
        privateRuntime = Self.openPrivateBrowsing(
            core: rootBrowser.core, sidebarIsPresented: sidebarIsPresented,
            downloads: privateDownloads)
        self.privateDownloads = privateDownloads
        self.windowState = windowState
        self.pageStoreRegistry = pageStoreRegistry
    }

    // MARK: - Actions - Window

    func activateWindow() {
        reopenIfClosed()
        pageStoreRegistry.register(pages)
        pageStoreRegistry.registerPrivateBrowsing(privatePages)
    }

    func cleanupDeferredWebsiteDataStores() async {
        await BrowserDeferredWebsiteDataStoreCleanup.cleanupPendingStores()
    }

    func sweepExpiredTabsWhileActive() async {
        await browser.sweepExpiredBrowsingDataWhileSceneIsActive {
            pages.downloadCenter.sweepExpiredRecords(in: browser.spaceModels)
        }
    }

    func prepareForInactiveScene() {
        flushPendingPersistence()
    }

    func prepareForBackgroundScene() {
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
        pageStoreRegistry.unregister(privatePages)
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
        synchronizeSidebarPresentation(navigation)
        return .standard
    }

    @discardableResult
    func routeExternalURL(_ url: URL) async -> Bool {
        guard ExternalWebLink.accepts(url),
            let placement = try? browser.core.query(
                ExternalOpenDestination(windowIDs: [browser.windowID])),
            let spaceID = placement.spaceID,
            let space = browser.spaceModel(spaceID)
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.spaceModel(matching: assignment) != nil else { return false }
        guard browser.openNewTab(url: url, matching: assignment) != nil else { return false }
        pages.selectAndNavigate(to: url.absoluteString)
        navigation.selectTab()
        return true
    }

    // MARK: - Actions - Private browsing

    /// A new private workspace in `core` and what shows it in this window.
    private static func openPrivateBrowsing(
        core: CrestCore, sidebarIsPresented: Bool,
        downloads: MobileBrowserDownloads?
    ) -> PrivateBrowsingRuntime {
        let privateBrowser = BrowserStore.privateBrowsing(core: core)
        let privateNavigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            allowsCompactFloatingSidebar: MobileBrowserRootPreferences.allowsFloatingSidebar
        )
        let privatePages = MobileBrowserPageStore(
            browser: privateBrowser,
            browsingMode: .privateBrowsing,
            permissionCenter: downloads?.center.permissionCenter ?? BrowserSitePermissionCenter(),
            downloads: downloads,
            linkDestinationHost: BrowserLinkDestinationHost(browser: privateBrowser),
            openModifiedLink: { url, spaceID, selecting in
                privateBrowser.openModifiedLink(url, in: spaceID, selecting: selecting)
            }
        )

        privateBrowser.tabLinkProvider = privatePages
        privateBrowser.tabCopying = privatePages
        return PrivateBrowsingRuntime(
            browser: privateBrowser, pages: privatePages, navigation: privateNavigation)
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
            core: browser.core, sidebarIsPresented: windowState.sidebarIsPresented ?? true,
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
