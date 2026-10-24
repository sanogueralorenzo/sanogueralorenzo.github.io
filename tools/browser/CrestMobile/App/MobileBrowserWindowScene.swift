import SwiftUI
import UIKit

struct MobileBrowserWindowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BrowserCloudSyncController.self) private var cloudSync

    private let onboardingProgress: BrowserOnboardingProgressStore
    private let automaticallyPresentsOnboarding: Bool
    private let sidebarWidgets: BrowserSidebarWidgetRuntime
    @Bindable private var onboardingCoordinator: BrowserOnboardingCoordinator

    @State private var runtime = Runtime()
    private let makeModel: @MainActor () -> MobileBrowserWindowSceneModel
    @State private var browsingMode: BrowserBrowsingMode = .standard
    @State private var hasPresentedAutomaticOnboarding = false

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
        usesEphemeralWebsiteDataStores: Bool,
        onboardingProgress: BrowserOnboardingProgressStore,
        onboardingCoordinator: BrowserOnboardingCoordinator,
        automaticallyPresentsOnboarding: Bool,
        mediaSessions: BrowserMediaSessionStore,
        downloads: MobileBrowserDownloads,
        privateDownloads: MobileBrowserDownloads,
        sidebarWidgets: BrowserSidebarWidgetRuntime
    ) {
        self.onboardingProgress = onboardingProgress
        self.onboardingCoordinator = onboardingCoordinator
        self.automaticallyPresentsOnboarding = automaticallyPresentsOnboarding
        self.sidebarWidgets = sidebarWidgets
        makeModel = {
            MobileBrowserWindowSceneModel(
                id: id,
                rootBrowser: rootBrowser,
                permissionCenter: permissionCenter,
                pageStoreRegistry: pageStoreRegistry,
                spaceAccess: spaceAccess,
                tabStateArchive: tabStateArchive,
                windowLayouts: windowLayouts,
                startupBehavior: startupBehavior,
                monitorsMemoryPressure: monitorsMemoryPressure,
                usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
                mediaSessionStore: mediaSessions,
                downloads: downloads,
                privateDownloads: privateDownloads
            )
        }
    }

    private var model: MobileBrowserWindowSceneModel { runtime.model(makingWith: makeModel) }

    /// Scene construction registers stores and reads shared observed state, so
    /// the holder builds the model the first time the scene reads it: once per
    /// mounted scene, in the scene's own update rather than its parent's body
    /// evaluation. The holder is the state's own default rather than a value
    /// `init` assigns, which would make SwiftUI update the scene each time its
    /// parent does. The model keeps Observation for UI updates.
    @MainActor
    private final class Runtime {
        private var built: MobileBrowserWindowSceneModel?

        func model(makingWith make: @MainActor () -> MobileBrowserWindowSceneModel) -> MobileBrowserWindowSceneModel {
            if let built { return built }
            let model = make()
            built = model
            return model
        }
    }

    var body: some View {
        sceneSurface
            .modifier(BrowserChromeAppearancePersistence())
            .environment(model.browser.core)
            .environment(model.browser.core.engines)
            .environment(\.browserInteractionCapabilities, BrowserInteractionCapabilities(supportsTouch: true))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                BrowserWindowAccessibilityID.scene(model.windowState.id)
            )
            .task {
                await model.cleanupDeferredWebsiteDataStores()
            }
            // Tab cleanup follows the scene: it sweeps as soon as the scene becomes
            // active and then keeps sweeping on a low-frequency tick, and SwiftUI
            // cancels the loop whenever the phase changes so a backgrounded scene
            // stops sweeping. Private browsing is left alone; those Spaces never clean
            // up, and the session goes away with the mode.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.sweepExpiredTabsWhileActive()
            }
            .onAppear(perform: activateWindow)
            .onDisappear(perform: closeWindowRuntime)
            .onOpenURL(perform: openExternalURL)
            // UIKit's warning supplements the kernel pressure source the standard store
            // watches: it only reaches a foregrounded app, but it is also the one signal
            // the private store gets, since private pages have no archive to come back
            // from. Both signals land on the same handler, which collapses the pair that
            // one squeeze produces into a single trim.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                model.handleMemoryPressure()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    activateWindow()
                case .inactive:
                    sidebarWidgets.suspendHost(id: model.windowState.id)
                    model.prepareForInactiveScene()
                case .background:
                    sidebarWidgets.suspendHost(id: model.windowState.id)
                    model.prepareForBackgroundScene()
                @unknown default:
                    sidebarWidgets.suspendHost(id: model.windowState.id)
                    model.prepareForBackgroundScene()
                }
            }
            .animation(
                CrestMotion.onboardingPresentation.unlessReducingMotion(reduceMotion),
                value: onboardingCoordinator.isMobilePresented
            )
            .onAppear(perform: presentAutomaticOnboardingIfNeeded)
    }

    private func activateWindow() {
        model.activateWindow()
        sidebarWidgets.activateHost(
            id: model.windowState.id,
            capabilities: [.mediaSessions]
        )
    }

    private func closeWindowRuntime() {
        sidebarWidgets.removeHost(id: model.windowState.id)
        model.closeWindowRuntime()
    }

    @ViewBuilder
    private var sceneSurface: some View {
        if showsAutomaticLaunchGate {
            onboardingSurface
        } else {
            browserSurfaceWithOnboardingOverlay
        }
    }

    private var browserSurfaceWithOnboardingOverlay: some View {
        ZStack {
            browserSurface
                .allowsHitTesting(!onboardingCoordinator.isMobilePresented)
                .accessibilityHidden(onboardingCoordinator.isMobilePresented)

            if onboardingCoordinator.isMobilePresented {
                onboardingSurface
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private var browserSurface: some View {
        if browsingMode.isPrivate {
            MobileBrowserRootView(
                browser: model.privateBrowser,
                pages: model.privatePages,
                dataDeleter: model.privatePages,
                navigation: model.privateNavigation,
                transientBrowsing: model.privateTransientBrowsing,
                windowState: model.windowState,
                suspendsCompactPagePresentation: onboardingCoordinator.isMobilePresented,
                startupBehavior: .lastActiveTab,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
            .preferredColorScheme(.dark)
        } else {
            MobileBrowserRootView(
                browser: model.browser,
                pages: model.pages,
                dataDeleter: model.pageStoreRegistry,
                navigation: model.navigation,
                transientBrowsing: model.transientBrowsing,
                spaceAccess: model.spaceAccess,
                windowState: model.windowState,
                suspendsCompactPagePresentation: onboardingCoordinator.isMobilePresented,
                startupBehavior: model.startupBehavior,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
        }
    }

    private var onboardingSurface: some View {
        MobileBrowserOnboardingView(
            request: onboardingCoordinator.request,
            browser: model.browser,
            cloudSync: cloudSync,
            progress: onboardingProgress,
            coordinator: onboardingCoordinator,
            spaceAccess: model.spaceAccess,
            didOpenGettingStarted: { assignment in
                if model.presentGettingStartedAfterSetup(matching: assignment) {
                    browsingMode = .standard
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var showsAutomaticLaunchGate: Bool {
        let gateIsActive =
            onboardingProgress.isLaunchGateActive
            && onboardingCoordinator.request.entryPoint == .firstRun
        return Self.showsLaunchGate(
            automaticallyPresentsOnboarding: automaticallyPresentsOnboarding,
            isLaunchGateActive: gateIsActive
        )
    }

    /// Whether a launch puts up the welcome by itself: always outside an
    /// isolated test launch, and inside one only when a fixture asks for it.
    nonisolated static func presentsOnboardingAutomatically(
        forceOnboarding: Bool,
        usesIsolatedLaunch: Bool
    ) -> Bool {
        forceOnboarding || !usesIsolatedLaunch
    }

    /// Whether the launch gate replaces the browser: only on an incomplete
    /// install whose welcome comes up by itself.
    nonisolated static func showsLaunchGate(
        automaticallyPresentsOnboarding: Bool,
        isLaunchGateActive: Bool
    ) -> Bool {
        automaticallyPresentsOnboarding && isLaunchGateActive
    }

    private func presentAutomaticOnboardingIfNeeded() {
        guard onboardingProgress.shouldPresentWelcome,
            automaticallyPresentsOnboarding,
            !hasPresentedAutomaticOnboarding
        else { return }
        onboardingCoordinator.presentOnMobile(.firstRun)
        hasPresentedAutomaticOnboarding = true
    }

    private func togglePrivateBrowsing() {
        let destinationMode = model.togglePrivateBrowsing(from: browsingMode)
        withAnimation(modeAnimation) {
            browsingMode = destinationMode
        }
    }

    private func closePrivateBrowsing() {
        let destinationMode = model.closePrivateBrowsing()
        withAnimation(modeAnimation) {
            browsingMode = destinationMode
        }
    }

    private func openExternalURL(_ url: URL) {
        BrowserPlatformDefaultBrowserSystem.noteOpenedLink(url)
        // The share sheet hands a link over as `crest://open`, which routes
        // as the web link it carries.
        let link = BrowserSharedLink(handOffURL: url)?.url ?? url
        Task {
            guard await model.routeExternalURL(link) else { return }
            withAnimation(modeAnimation) {
                browsingMode = .standard
            }
        }
    }

    private var modeAnimation: Animation? {
        CrestMotion.navigation.unlessReducingMotion(reduceMotion)
    }
}
