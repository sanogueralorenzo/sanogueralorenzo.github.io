import AppKit
import SwiftUI

struct BrowserMacWindowScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.browserMacWindows) private var windows

    let model: BrowserMacWindowModel
    let coordinator: BrowserMacWindowCoordinator
    @State private var closed = false
    var id: UUID { model.id }
    var browser: BrowserStore { model.browser }
    var pages: BrowserPagePool { model.pages }
    var chrome: BrowserChromeState { model.chrome }
    var windowState: BrowserWindowStateStore { model.windowState }
    private let pagePoolRegistry: BrowserPagePoolRegistry
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let shortcuts: BrowserShortcutStore?
    private let softwareUpdates: BrowserSoftwareUpdateService

    init(
        model: BrowserMacWindowModel,
        coordinator: BrowserMacWindowCoordinator,
        pagePoolRegistry: BrowserPagePoolRegistry,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState,
        shortcuts: BrowserShortcutStore? = nil,
        softwareUpdates: BrowserSoftwareUpdateService
    ) {
        self.model = model
        self.coordinator = coordinator
        self.pagePoolRegistry = pagePoolRegistry
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.shortcuts = shortcuts
        self.softwareUpdates = softwareUpdates
    }

    var body: some View {
        BrowserRootView(
            browser: browser,
            pages: pages,
            chrome: chrome,

            windowState: windowState,
            spaceSettingsPresentation: model.spaceSettingsPresentation,
            shortcuts: shortcuts
        )
        .modifier(BrowserChromeAppearancePersistence())
        .frame(
            minWidth: BrowserMacWindowKind.browserMinimumContentSize.width,
            idealWidth: BrowserMacWindowKind.browserContentSize.width,
            maxWidth: .infinity,
            minHeight: BrowserMacWindowKind.browserMinimumContentSize.height,
            idealHeight: BrowserMacWindowKind.browserContentSize.height,
            maxHeight: .infinity
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserWindowAccessibilityID.scene(id)
        )
        .environment(\.browserPagePresentationWindowID, id)
        .environment(
            \.browserSidebarWindowDrop,
            BrowserSidebarWindowDrop(
                windowID: id,
                perform: handleWindowDrop,
                didMeasureRow: { coordinator.didMeasureRow($0, in: id) })
        )
        .background(
            BrowserMacWindowAttachment(
                prepare: { coordinator.preparePresentation($0, for: id) },
                attach: { window in
                    guard coordinator.attach(window, to: id) else { return }
                    activateWindow()
                    pages.setWindowFocused(window.isKeyWindow)
                },
                focusChanged: { focused in
                    pages.setWindowFocused(focused)
                },
                close: closeWindowRuntime)
        )
        .onAppear(perform: activateWindow)
        .modifier(BrowserTemporaryWorkspaceReconciliation(coordinator: coordinator))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
        }
        .onDisappear(perform: closeWindowRuntime)
        .task {
            await BrowserDeferredWebsiteDataStoreCleanup.cleanupPendingStores()
        }
        // Retention cleanup follows the scene: it sweeps as soon as this window becomes
        // active and then keeps sweeping on a low-frequency tick, and SwiftUI
        // cancels the loop whenever the phase changes so an inactive window stops
        // sweeping. Windows share one session, which collapses overlapping sweeps.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await browser.sweepExpiredBrowsingDataWhileSceneIsActive {
                pages.downloadCenter.sweepExpiredRecords(in: browser.spaceModels)
            }
        }
        .onChange(of: spaceSettingsPresentation.revision) {
            guard model.window?.isKeyWindow == true,
                let assignment = spaceSettingsPresentation.requestedAssignment,
                browser.spaceModel(matching: assignment) != nil
            else { return }
            model.spaceSettingsPresentation.present(
                spaceSettingsPresentation.request, assignment: assignment,
                searchText: spaceSettingsPresentation.searchText)
            browser.selectSpace(assignment.spaceID)
            browser.openSettings()
            pages.select()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                activateWindow()
            } else {
                flushPendingPersistence()
            }
        }
    }

    private func activateWindow() {
        softwareUpdates.applicationDidBecomeActive()
        pagePoolRegistry.register(
            pages,
            browser: browser,
            for: id
        )
    }

    private func closeWindowRuntime() {
        guard !closed else { return }
        closed = true
        (browser.interactionObserver as? BrowserSidebarInteractionState)?.cancel()
        pagePoolRegistry.unregister(pages, for: id)
        flushPendingPersistence()
        coordinator.closeWindow(id)
    }

    private func handleWindowDrop(_ lift: BrowserSidebarFloatingLift) -> Bool {
        let event = NSApp.currentEvent
        let point =
            event.flatMap { event in
                event.window?.convertPoint(toScreen: event.locationInWindow)
            } ?? NSEvent.mouseLocation
        return BrowserMacWindowDropAction(
            coordinator: coordinator, sourceWindowID: id,
            open: { [windows] request in windows?.open(request, activation: .key) }
        ).perform(lift.item, at: point, grabFraction: lift.anchorFraction)
    }

    private func flushPendingPersistence() {
        // Reading each resident page's WebKit session state has to happen while
        // the pages are still resident, so it is captured here rather than inside
        // the detached flush.
        pages.archiveResidentTabStates()
        Task {
            await browser.flushPendingSyncPersistence()
            await pages.flushPendingTabStateWrites()
        }
    }
}

/// Showing a tab moves the session revision, so the scene follows it in a
/// modifier of its own: the window's body, and the environment it writes for
/// every view below it, stay as they are.
private struct BrowserTemporaryWorkspaceReconciliation: ViewModifier {
    let coordinator: BrowserMacWindowCoordinator

    func body(content: Content) -> some View {
        content.onChange(of: coordinator.browser.sessionRevision) {
            coordinator.reconcileTemporaryWorkspaces()
        }
    }
}
