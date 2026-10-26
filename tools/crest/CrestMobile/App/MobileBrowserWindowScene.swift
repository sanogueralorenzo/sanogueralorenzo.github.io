import SwiftUI
import UIKit

struct MobileBrowserWindowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BrowserCloudSyncController.self) private var cloudSync

    private let memoryPressure: BrowserMemoryPressureMonitor

    @State private var runtime = Runtime()
    private let makeModel: @MainActor () -> MobileBrowserWindowSceneModel
    @State private var browsingMode: BrowserBrowsingMode = .standard

    init(
        id: UUID,
        rootBrowser: BrowserStore,
        permissionCenter: BrowserSitePermissionCenter,
        pageStoreRegistry: MobileBrowserPageStoreRegistry,
        tabStateArchive: (any BrowserTabStateArchiving)?,
        windowLayouts: BrowserWindowLayouts,
        memoryPressure: BrowserMemoryPressureMonitor,
        usesEphemeralWebsiteDataStores: Bool,
        mediaSessions: BrowserMediaSessionStore,
        downloads: MobileBrowserDownloads,
        privateDownloads: MobileBrowserDownloads
    ) {
        self.memoryPressure = memoryPressure
        makeModel = {
            MobileBrowserWindowSceneModel(
                id: id,
                rootBrowser: rootBrowser,
                permissionCenter: permissionCenter,
                pageStoreRegistry: pageStoreRegistry,
                tabStateArchive: tabStateArchive,
                windowLayouts: windowLayouts,
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
        browserSurface
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
            // UIKit's warning supplements the kernel pressure source, and reaches a
            // foregrounded app only. Every scene hears it, and the app's one monitor
            // collapses those and the kernel's event for one squeeze into a single
            // relief of every window's pages.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                memoryPressure.relieve(.critical)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    activateWindow()
                case .inactive:
                    model.prepareForInactiveScene()
                case .background:
                    model.prepareForBackgroundScene()
                @unknown default:
                    model.prepareForBackgroundScene()
                }
            }
    }

    private func activateWindow() {
        model.activateWindow()

    }

    private func closeWindowRuntime() {
        model.closeWindowRuntime()
    }

    @ViewBuilder
    private var browserSurface: some View {
        if browsingMode.isPrivate {
            MobileBrowserRootView(
                browser: model.privateBrowser,
                pages: model.privatePages,
                dataDeleter: model.privatePages,
                navigation: model.privateNavigation,

                windowState: model.windowState,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
        } else {
            MobileBrowserRootView(
                browser: model.browser,
                pages: model.pages,
                dataDeleter: model.pageStoreRegistry,
                navigation: model.navigation,

                windowState: model.windowState,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
        }
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
