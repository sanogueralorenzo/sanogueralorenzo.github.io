import SwiftUI
import UserNotifications

/// The application's services, which the Mac shell runs for whichever
/// engine's product owns the process, and the window content every product
/// shows.
@MainActor
final class BrowserMacApplication {
    let hostedNotificationCenter: BrowserHostedWebNotificationSystemCenter
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let onboardingProgress: BrowserOnboardingProgressStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let windowCoordinator: BrowserMacWindowCoordinator
    let privateBrowser: BrowserStore
    let privatePages: BrowserPagePool
    let privateChrome: BrowserChromeState
    let privateTransientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    /// The app's one passkey controller: pages refresh it and settings show it.
    let passkeyAccess: BrowserPasskeyAccessController
    /// Whether agents can reach Crest now: the agent service keeps it and
    /// settings show it.
    let agentEndpoint = BrowserAgentEndpointStatus()
    let shortcuts: BrowserShortcutStore
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let softwareUpdates: BrowserSoftwareUpdateService
    let sidebarWidgets: BrowserSidebarWidgetRuntime
    let pagePoolRegistry: BrowserPagePoolRegistry
    /// Asks the core whether the app may quit, and the person about downloads
    /// in progress.
    let quitPreparation: BrowserQuitPreparation
    /// Whether the private window may close when the person asks: closing it
    /// ends private browsing, so the core asks every page it hosts, its Quick
    /// Windows' too.
    let privateWindowCloseGate: BrowserWindowCloseGate
    /// Answers the core's questions about every engine's downloads: where each
    /// file goes, and whether to keep one its engine warned about.
    let downloadPrompts: BrowserDownloadPrompts
    /// Offers a switch to another engine for protected video, and a way back.
    let engineMoveNotices: BrowserEngineMoveNotices
    /// Follows the system's memory pressure for every window's pages; nil in
    /// an isolated launch, which leaves its pages alone.
    let memoryPressure: BrowserMemoryPressureMonitor?
    let systemNowPlaying: BrowserSystemNowPlayingCoordinator?
    let startupBehavior: StartupBehavior
    /// The window that opens on `startupBehavior`: the frontmost of the
    /// windows the launch opened. Every other window opens on the tab it left.
    var startupWindowID = BrowserMacWindowRequest.initial.id
    let presentsInstalledApplicationUI: Bool
    /// Whether a tool started Crest in the background, so the launch's
    /// windows open without taking focus.
    let launchesInBackground: Bool
    /// The launch flags as the core reads them.
    let launchEnvironment: LaunchEnvironment
    /// The view an engine anchors its popups to behind Site Controls.
    let siteControlAnchor: BrowserSiteControlAnchor?

    /// The browser windows, frontmost first, by the identity each has in the
    /// core: the order AppKit stacks them in, then any it leaves out, such as
    /// a minimized one. The core's window decisions read them in this order.
    var stackedWindowIDs: [UUID] {
        let pools = [privatePages] + windowCoordinator.openWindowPages
        let windows = pools.compactMap { pool in pool.presentationWindow.map { (window: $0, id: pool.windowID) } }
        let stacked = NSApp.orderedWindows.compactMap { window in windows.first { $0.window === window }?.id }
        return stacked + windows.map(\.id).filter { !stacked.contains($0) }
    }

    /// - Parameters:
    ///   - defaultEngine: The engine new pages open on; nil makes it WebKit,
    ///     which every composition registers.
    ///   - siteControlAnchor: A view an engine anchors its popups to behind
    ///     each window's Site Controls button.
    ///   - reviewPersistenceID: The isolated store a review build of this
    ///     composition keeps, so each engine's review app has its own. A test
    ///     run the review build hosts keeps nothing, as in every other host.
    init(
        defaultEngine: (any NativeEngineBinding)? = nil,
        siteControlAnchor: BrowserSiteControlAnchor? = nil,
        reviewPersistenceID: String = "core-native-ui-review"
    ) throws {
        self.siteControlAnchor = siteControlAnchor
        #if CREST_REVIEW_BUILD
            // Naming the review's isolation under a test run would open the
            // review app's own session, credentials and website data stores.
            if !BrowserLaunchEnvironment.current.isXCTestRuntime {
                setenv("CREST_ISOLATED_SESSION", "1", 1)
                setenv("CREST_ISOLATED_PERSISTENCE_ID", reviewPersistenceID, 0)
            }
        #endif
        let launchEnvironment = BrowserLaunchEnvironment.current
        let usesIsolatedLaunch = launchEnvironment.requiresIsolation
        let usesEphemeralProfileStorage =
            launchEnvironment.usesEphemeralProfileStorage
        BrowserMacWebTextAssistancePreference.configure()
        BrowserWebKitFeatureFlagStore.configureForLaunch(
            usesIsolatedLaunch: usesIsolatedLaunch
        )
        let utilityDefaults: UserDefaults? = usesIsolatedLaunch ? nil : .standard
        presentsInstalledApplicationUI =
            launchEnvironment.presentsInstalledApplicationUI
        launchesInBackground = launchEnvironment.launchesInBackground
        // Import review and manual setup belong to the currently open wizard.
        // Retire drafts written by earlier releases before any new window opens.
        if !usesIsolatedLaunch {
            BrowserOnboardingLegacyDraftCleanup.clear()
        }
        // One core per process. It keeps the session file, every window of
        // both browsing modes shares it, and standard and private windows each
        // share one download center over it.
        let core = try BrowserStore.launchCore(for: launchEnvironment)
        core.engines.register(
            WebKitEngineBinding(keepsProfilesInMemory: usesEphemeralProfileStorage), isDefault: defaultEngine == nil)
        if let defaultEngine { core.engines.register(defaultEngine, isDefault: true) }
        // The core's device store keeps what an older release kept in its
        // defaults, carried once; the link preferences come first, since every
        // window's store reads them.
        let legacyDevice = BrowserLegacyDeviceDefaults.read(for: launchEnvironment)
        BrowserLinkPreferenceStore.adopt(legacyDevice.linkPreferences, into: core)
        let browser = try BrowserStore.production(core: core, launchEnvironment: launchEnvironment)
        // The search catalog carries the engines the Spaces chose before the
        // device kept one, so it restores once the stored session is open.
        BrowserSearchCatalog.restore(into: core)
        BrowserAppPreferenceStore.shared.bind(
            to: browser, legacy: LegacyAppPreferences.read(for: launchEnvironment))
        BrowserAppPreferenceStore.shared.reconcileWebKitSpellChecking()
        let privateBrowser = BrowserStore.privateBrowsing(core: core)
        let passkeyAccess = BrowserPasskeyAccessController(core: core)
        let cloudSync =
            usesIsolatedLaunch
            ? BrowserCloudSyncController.isolated(core: core)
            : BrowserCloudSyncController(core: core)
        core.syncJournalChangeHandler = { [weak cloudSync] in
            Task { await cloudSync?.localChangesDidStage() }
        }
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let privateTransientBrowsing = BrowserTransientBrowsingCoordinator()
        let spaceAccess = BrowserSpaceAccessController()
        spaceAccess.announce = { message in
            BrowserNoticeCenter.shared.post(BrowserNotice(message: message, systemImage: "lock.fill"))
        }
        browser.attachSpaceAccess(spaceAccess)
        privateBrowser.attachSpaceAccess(spaceAccess)
        let spaceSettingsPresentation =
            BrowserSpaceSettingsPresentationState()
        // The core keeps every Space's site permission choices and decides
        // which ones the device store keeps: never a private Space's.
        let permissionCenter = BrowserSitePermissionCenter(core: core)
        permissionCenter.adoptLegacyRecords(legacyDevice.sitePermissions)
        let hostedNotificationCenter = BrowserHostedWebNotificationSystemCenter()
        self.hostedNotificationCenter = hostedNotificationCenter
        let sidebarDefaults: UserDefaults?
        if usesIsolatedLaunch, let isolationID = launchEnvironment.persistentIsolationID {
            sidebarDefaults = UserDefaults(
                suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID))
        } else {
            sidebarDefaults = utilityDefaults
        }
        // An isolated launch keeps its engine session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive = BrowserTabStateArchive.forLaunch(launchEnvironment)
        let mediaSessions = BrowserMediaSessionStore()
        let systemNowPlaying =
            presentsInstalledApplicationUI
            ? BrowserSystemNowPlayingCoordinator(store: mediaSessions)
            : nil
        systemNowPlaying?.start()
        let isolatedSoftwareUpdateFeed =
            launchEnvironment.isolatedSoftwareUpdateFeedURL
        let softwareUpdates = BrowserSoftwareUpdateService(
            isEnabled: presentsInstalledApplicationUI
                && (!usesIsolatedLaunch || isolatedSoftwareUpdateFeed != nil),
            preferences: usesIsolatedLaunch ? nil : .standard,
            defaultChannel: isolatedSoftwareUpdateFeed.map { _ in .development },
            feedURLOverride: isolatedSoftwareUpdateFeed
        )
        if usesIsolatedLaunch,
            let fixture = launchEnvironment.softwareUpdateWidgetFixture
        {
            softwareUpdates.presentIsolatedSidebarWidgetFixture(fixture)
        }
        let sidebarWidgetPreferences = BrowserSidebarWidgetPreferenceStore.launch(
            environment: launchEnvironment
        )
        let sidebarWidgets = BrowserSidebarWidgetRuntime(
            registrations: [.softwareUpdate, .nowPlaying],
            sources: [softwareUpdates.widgetSource, mediaSessions],
            preferences: sidebarWidgetPreferences
        )
        if launchEnvironment.presentsShowcaseSession, let profileID = browser.shownSpace?.profileID {
            core.addShowcaseDownloads(profileID: profileID)
        }
        let pages = BrowserPagePool(
            browser: browser,
            usesEphemeralWebsiteDataStores: usesEphemeralProfileStorage,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            mediaSessionStore: mediaSessions,
            passkeyAccess: passkeyAccess,
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
            openNewTab: { url in browser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                browser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in transientBrowsing.presentPeek(request) },
            handleLinkDrag: { transientBrowsing.handleLinkDrag($0) },
            splitLinkHost: browser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            activateHostedNotificationSource: { spaceID, tabID in
                browser.selectSpace(spaceID)
                browser.selectTab(tabID)
            }
        )
        let privatePages = BrowserPagePool(
            browser: privateBrowser,
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter,
            passkeyAccess: passkeyAccess,
            openNewTab: { url in privateBrowser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                privateBrowser.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in privateTransientBrowsing.presentPeek(request) },
            handleLinkDrag: { privateTransientBrowsing.handleLinkDrag($0) },
            splitLinkHost: privateBrowser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: privateBrowser, spaceAccess: spaceAccess)
        )
        browser.tabLinkProvider = pages
        privateBrowser.tabLinkProvider = privatePages
        browser.tabCopying = pages
        privateBrowser.tabCopying = privatePages
        let windowLayouts = BrowserWindowLayouts(defaults: sidebarDefaults)
        // The device store keeps whether setup was completed here, carried
        // once from what an older release kept in its defaults.
        _ = try? core.send(AdoptSetupCompletion(completed: legacyDevice.setupCompleted))
        let onboardingProgress = BrowserOnboardingProgressStore(
            core: core, environment: launchEnvironment.coreEnvironment,
            forcesSetup: launchEnvironment.forcesMacOnboardingSetup)
        let startupBehavior = browser.startupBehavior(for: launchEnvironment)
        // The core carries what each window showed into its own records once;
        // launch cleanup then keeps every tab a saved window will show.
        windowLayouts.adoptLegacyRecords(into: core)
        browser.sweepAtLaunch()
        self.browser = browser
        self.cloudSync = cloudSync
        self.onboardingProgress = onboardingProgress
        let initialLayout = windowLayouts.layout(for: BrowserMacWindowRequest.initial.id)
        self.chrome = BrowserChromeState(
            sidebarIsPresented: initialLayout?.sidebarIsPresented ?? true,
            utilityPresentation: BrowserUtilityPresentationState(
                defaults: utilityDefaults
            )
        )
        self.transientBrowsing = transientBrowsing
        self.windowCoordinator = BrowserMacWindowCoordinator(
            browser: browser, pages: pages, spaceAccess: spaceAccess, windowLayouts: windowLayouts)
        self.privateBrowser = privateBrowser
        self.privateChrome = BrowserChromeState(
            utilityPresentation: BrowserUtilityPresentationState(
                defaults: utilityDefaults
            )
        )
        self.privateTransientBrowsing = privateTransientBrowsing
        self.spaceAccess = spaceAccess
        self.spaceSettingsPresentation = spaceSettingsPresentation
        let shortcuts = BrowserShortcutStore(core: core, legacyOverrides: legacyDevice.shortcuts)
        self.shortcuts = shortcuts
        self.passkeyAccess = passkeyAccess
        self.softwareUpdates = softwareUpdates
        self.sidebarWidgets = sidebarWidgets
        self.pages = pages
        self.privatePages = privatePages
        pagePoolRegistry = BrowserPagePoolRegistry(primary: pages, spaceAccess: spaceAccess)
        quitPreparation = BrowserQuitPreparation(core: core) {
            browser.family.activeSpaceDeletions.union(privateBrowser.family.activeSpaceDeletions)
        }
        privateWindowCloseGate = BrowserWindowCloseGate(core: core) { [windowID = privateBrowser.windowID] in
            PrepareToCloseWindows(requestID: UUID(), windowIDs: [windowID])
        }
        engineMoveNotices = BrowserEngineMoveNotices(core: core)
        let downloadDialogs = BrowserDialogPresenter()
        downloadPrompts = BrowserDownloadPrompts(core: core) { asked, dismissal in
            let spaceName = asked.spaceID.flatMap {
                browser.spaceModel($0)?.settings.name ?? privateBrowser.spaceModel($0)?.settings.name
            }
            return await downloadDialogs.approveDownload(asked, spaceName: spaceName, dismissal: dismissal)
        }
        self.systemNowPlaying = systemNowPlaying
        self.startupBehavior = startupBehavior
        self.launchEnvironment = launchEnvironment.coreEnvironment
        memoryPressure = usesIsolatedLaunch ? nil : BrowserMemoryPressureMonitor(core: core, pools: pagePoolRegistry)
        browser.family.configureSpaceDataCleanup(pagePoolRegistry, from: browser)
        memoryPressure?.start()
    }

    func settingsTabContent(
        browser: BrowserStore, pages: BrowserPagePool,
        presentation: BrowserSpaceSettingsPresentationState? = nil
    ) -> BrowserSettingsTabContent {
        BrowserSettingsTabContent { [self] runtime in
            BrowserSettingsView(
                browser: browser.profileSettingsBrowser, pages: pages, cloudSync: cloudSync,
                spaceAccess: spaceAccess, dataDeleter: pagePoolRegistry, shortcuts: shortcuts,
                spaceSettingsPresentation: presentation ?? spaceSettingsPresentation,
                usesLiveSidebar: !browser.isTemporaryWorkspace,
                tabState: runtime.model(BrowserSettingsTabState.self) { BrowserSettingsTabState() },
                tabAssignment: runtime.assignment
            )
        }
    }

    /// What the browser window `model` shows.
    func browserWindowContent(_ model: BrowserMacWindowModel) -> some View {
        BrowserMacWindowScene(
            model: model, coordinator: windowCoordinator,
            pagePoolRegistry: pagePoolRegistry, spaceAccess: spaceAccess,
            spaceSettingsPresentation: spaceSettingsPresentation,
            startupBehavior: model.id == startupWindowID ? startupBehavior : .lastActiveTab,
            shortcuts: shortcuts, sidebarWidgets: sidebarWidgets, softwareUpdates: softwareUpdates
        )
        .environment(
            \.browserSettingsTabContent,
            settingsTabContent(
                browser: model.browser, pages: model.pages, presentation: model.spaceSettingsPresentation)
        )
        .environment(softwareUpdates)
        .environment(passkeyAccess)
        .environment(agentEndpoint)
        .environment(browser.core)
        .environment(browser.core.engines)
        .environment(\.browserSidebarWidgetRuntime, sidebarWidgets)
        .environment(\.browserSiteControlAnchor, siteControlAnchor)
        .modifier(BrowserSoftwareUpdateDetailsPresentation())
    }

    var privateWindowContent: some View {
        BrowserRootView(
            browser: privateBrowser,
            pages: privatePages,
            chrome: privateChrome,
            transientBrowsing: privateTransientBrowsing,
            startupBehavior: .lastActiveTab,
            shortcuts: shortcuts
        )
        .modifier(BrowserChromeAppearancePersistence())
        .environment(softwareUpdates)
        .environment(passkeyAccess)
        .environment(agentEndpoint)
        .environment(privateBrowser.core)
        .environment(privateBrowser.core.engines)
        .environment(
            \.browserSidebarWidgetRuntime,
            sidebarWidgets
        )
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
        .environment(
            \.browserSettingsTabContent, settingsTabContent(browser: privateBrowser, pages: privatePages)
        )
        .environment(\.browserSiteControlAnchor, siteControlAnchor)
        .modifier(BrowserSoftwareUpdateDetailsPresentation())
        .background(
            BrowserMacWindowAttachment(
                attach: { window in
                    self.privatePages.bindNativeWindow(window)
                    self.privatePages.setWindowFocused(window.isKeyWindow)
                },
                focusChanged: { self.privatePages.setWindowFocused($0) },
                close: {
                    self.privatePages.setWindowFocused(false)
                    self.privatePages.bindNativeWindow(nil)
                }
            )
        )
    }

    /// Keeps the browser windows open now, as AppKit stacks them, for the
    /// next launch to reopen. Sent once a quit is allowed, before any window
    /// closes as the app goes; the core saves them before it returns.
    func rememberWindowsForLaunch() {
        _ = try? browser.core.send(RememberWindowsForLaunch(windowIDs: stackedWindowIDs))
    }

    func closePrivateBrowsingWindow() {
        privatePages.closePrivateBrowsingSession(
            privateBrowser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        privateBrowser.resetPrivateBrowsingSession()
        privateChrome.dismissCommandPalette()
        privateTransientBrowsing.dismissPeek()
    }

}
