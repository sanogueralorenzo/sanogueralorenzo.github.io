import SwiftUI

@main
struct CrestMobileApp: App {
    @State private var launch = BrowserApplicationLaunch { try BrowserMobileApplication() }

    var body: some Scene {
        WindowGroup(for: MobileWindowRequest.self) { $request in
            Group {
                if let application = launch.value, application.presentsInstalledApplicationUI {
                    application.windowContent(id: request.id)
                } else if launch.failure != nil {
                    BrowserSessionRecoveryView(launch: launch)
                } else {
                    EmptyView()
                }
            }
        } defaultValue: {
            MobileWindowRequest()
        }
        .commands {
            if let application = launch.value {
                MobileBrowserCommands(shortcuts: application.shortcuts)
            }
        }
    }
}

@MainActor
private final class BrowserMobileApplication {
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let onboardingProgress: BrowserOnboardingProgressStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    /// The app's one passkey controller, which settings show.
    let passkeyAccess: BrowserPasskeyAccessController
    let shortcuts: BrowserShortcutStore
    let sidebarWidgets: BrowserSidebarWidgetRuntime
    let permissionCenter: BrowserSitePermissionCenter
    let pageStoreRegistry: MobileBrowserPageStoreRegistry
    let mediaSessions: BrowserMediaSessionStore
    /// Every window shares one download center per browsing mode, over the
    /// process's one core.
    let downloads: MobileBrowserDownloads
    let privateDownloads: MobileBrowserDownloads
    let tabStateArchive: (any BrowserTabStateArchiving)?
    let windowLayouts: BrowserWindowLayouts
    let startupBehavior: StartupBehavior
    let automaticallyPresentsOnboarding: Bool
    let usesEphemeralWebsiteDataStores: Bool
    let presentsInstalledApplicationUI: Bool
    /// The app's one memory pressure monitor, which relieves every window's
    /// pages. The kernel's pressure events reach the app in the background and
    /// ahead of UIKit's warning, so they get ahead of a termination. Only an
    /// installed launch watches them; an isolated launch keeps its residency
    /// exactly where a test put it, and hears only UIKit's memory warning.
    let memoryPressure: BrowserMemoryPressureMonitor

    init() throws {
        #if CREST_REVIEW_BUILD
            setenv("CREST_ISOLATED_SESSION", "1", 1)
            setenv("CREST_ISOLATED_PERSISTENCE_ID", "core-native-ui-review", 0)
        #endif
        let launchEnvironment = BrowserLaunchEnvironment.current
        let forceOnboarding = launchEnvironment.forcesOnboardingWelcome
        let usesIsolatedLaunch = launchEnvironment.requiresIsolation
        BrowserAutomaticQuoteSubstitutionPreference.registerDefault()
        presentsInstalledApplicationUI =
            launchEnvironment.presentsInstalledApplicationUI
        // One core per process, keeping the session file and shared by every
        // window of both browsing modes.
        let core = try BrowserStore.launchCore(for: launchEnvironment)
        // An isolated launch keeps every profile's website data in memory.
        core.engines.register(WebKitEngineBinding(keepsProfilesInMemory: usesIsolatedLaunch), isDefault: true)
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
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let cloudSync =
            usesIsolatedLaunch
            ? BrowserCloudSyncController.isolated(core: core)
            : BrowserCloudSyncController(core: core)
        core.syncJournalChangeHandler = { [weak cloudSync] in
            Task { await cloudSync?.localChangesDidStage() }
        }
        let spaceAccess = BrowserSpaceAccessController()
        browser.attachSpaceAccess(spaceAccess)
        // The core keeps every Space's site permission choices and decides
        // which ones the device store keeps: never a private Space's.
        let permissionCenter = BrowserSitePermissionCenter(core: core)
        permissionCenter.adoptLegacyRecords(legacyDevice.sitePermissions)
        // An unfinished manual setup waits in the device store for onboarding
        // to go on with it.
        _ = try? core.send(AdoptSetupDraft(draft: legacyDevice.manualSetupDraft))
        // An isolated launch keeps its engine session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive = BrowserTabStateArchive.forLaunch(launchEnvironment)
        let mediaSessions = BrowserMediaSessionStore()
        let sidebarWidgetPreferences = BrowserSidebarWidgetPreferenceStore.launch(
            environment: launchEnvironment
        )
        let sidebarWidgets = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [mediaSessions],
            preferences: sidebarWidgetPreferences
        )
        if launchEnvironment.presentsShowcaseSession, let profileID = browser.shownSpace?.profileID {
            core.addShowcaseDownloads(profileID: profileID)
        }
        let downloads = MobileBrowserDownloads(core: core, permissionCenter: permissionCenter)
        let privateDownloads = MobileBrowserDownloads(
            core: core,
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter
        )
        let pages = MobileBrowserPageStore(
            window: browser, usesEphemeralWebsiteDataStores: usesIsolatedLaunch,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessions, downloads: downloads, tabStateArchive: tabStateArchive,
            spaceAccess: spaceAccess, transientBrowsing: transientBrowsing)

        self.browser = browser
        self.cloudSync = cloudSync
        // The device store keeps whether setup was completed here, carried
        // once from what an older release kept in its defaults.
        _ = try? core.send(AdoptSetupCompletion(completed: legacyDevice.setupCompleted))
        onboardingProgress = BrowserOnboardingProgressStore(
            core: core, environment: launchEnvironment.coreEnvironment,
            forcesSetup: launchEnvironment.forcesMobileOnboardingSetup)
        let onboardingCoordinator = BrowserOnboardingCoordinator()
        self.onboardingCoordinator = onboardingCoordinator
        self.pages = pages
        self.spaceAccess = spaceAccess
        passkeyAccess = BrowserPasskeyAccessController(core: core)
        self.sidebarWidgets = sidebarWidgets
        // A hardware keyboard on iPad reads the same rebindable command table
        // the Mac menu bar does, composed exactly the way the Mac composes it.
        shortcuts = BrowserShortcutStore(core: core, legacyOverrides: legacyDevice.shortcuts)
        self.permissionCenter = permissionCenter
        let pageStoreRegistry = MobileBrowserPageStoreRegistry(primary: pages)
        self.pageStoreRegistry = pageStoreRegistry
        self.mediaSessions = mediaSessions
        self.downloads = downloads
        self.privateDownloads = privateDownloads
        self.tabStateArchive = tabStateArchive
        if usesIsolatedLaunch {
            windowLayouts = BrowserWindowLayouts(
                defaults: launchEnvironment.persistentIsolationID.flatMap {
                    UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
                })
        } else {
            windowLayouts = BrowserWindowLayouts(defaults: .standard)
        }
        // The core carries what each scene showed into its own records once;
        // scenes restore from them later, and launch cleanup keeps every tab
        // one of them will show.
        windowLayouts.adoptLegacyRecords(into: core)
        browser.sweepAtLaunch()
        automaticallyPresentsOnboarding =
            MobileBrowserWindowScene
            .presentsOnboardingAutomatically(
                forceOnboarding: forceOnboarding,
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        startupBehavior = browser.startupBehavior(for: launchEnvironment)
        let memoryPressure = BrowserMemoryPressureMonitor(core: core) { [pageStoreRegistry] in
            pageStoreRegistry.liveStores
        }
        if !usesIsolatedLaunch { memoryPressure.start() }
        self.memoryPressure = memoryPressure
        usesEphemeralWebsiteDataStores = usesIsolatedLaunch
    }

    func windowContent(id windowID: UUID) -> some View {
        MobileBrowserWindowScene(
            id: windowID,
            rootBrowser: browser,
            permissionCenter: permissionCenter,
            pageStoreRegistry: pageStoreRegistry,
            spaceAccess: spaceAccess,
            tabStateArchive: tabStateArchive,
            windowLayouts: windowLayouts,
            startupBehavior: startupBehavior,
            memoryPressure: memoryPressure,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            onboardingProgress: onboardingProgress,
            onboardingCoordinator: onboardingCoordinator,
            automaticallyPresentsOnboarding: automaticallyPresentsOnboarding,
            mediaSessions: mediaSessions,
            downloads: downloads,
            privateDownloads: privateDownloads,
            sidebarWidgets: sidebarWidgets
        )
        .environment(cloudSync)
        .environment(onboardingCoordinator)
        .environment(passkeyAccess)
        .environment(
            \.browserSidebarWidgetRuntime,
            sidebarWidgets
        )
        .task {
            self.browser.family.configureSpaceDataCleanup(self.pageStoreRegistry, from: self.browser)
            await self.cloudSync.start()
        }
    }
}
