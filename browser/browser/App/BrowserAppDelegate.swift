import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class BrowserAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var owner: BrowserSessionOwner?
    var windows: [UUID: NSWindow] = [:]
    private var approvedCloses: Set<UUID> = []
    private var preparingCloses: Set<UUID> = []
    private var preparingQuit = false
    private var pendingLaunchURLs: [URL] = []
    private var startupWindow: BrowserWindow?
    private var launchTask: Task<Void, Never>?
    private var browserReady = false
    private var cliServer: BrowserCLIServer?
    private var pointerMonitor: Any?
    private var keyboardMonitor: Any?
    private let usesReviewProfile = ProcessInfo.processInfo.environment["BROWSER_REVIEW_DATA_DIRECTORY"] != nil
    var store: BrowserStore? {
        guard let owner else { return nil }
        if let id = owner.activeWindowID, let context = owner.contexts[id], !context.isClosed { return context }
        return owner.contexts.values.first { !$0.isClosed }
    }
    var window: NSWindow? { store.flatMap { windows[$0.id] } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for key in [
            "WebContinuousSpellCheckingEnabled", "WebAutomaticSpellingCorrectionEnabled", "WebGrammarCheckingEnabled",
            "WebSmartInsertDeleteEnabled", "WebSmartListsEnabled", "WebAutomaticQuoteSubstitutionEnabled",
            "WebAutomaticDashSubstitutionEnabled", "WebAutomaticLinkDetectionEnabled",
        ] { UserDefaults.standard.set(false, forKey: key) }
        do {
            let owner = try BrowserSessionOwner()
            self.owner = owner
            owner.openWindow = { [weak self] state in self?.createWindow(restoring: state) }
            owner.media = BrowserSystemMedia(owner: owner)
            UNUserNotificationCenter.current().delegate = self
            let startup = BrowserContentStartup(owner: owner)
            installMenu()
            launchTask = Task { [weak self] in
                guard await startup.prepare(report: { self?.showStartup($0) }),
                    !Task.isCancelled, let self
                else { return }
                finishLaunching(owner)
                await startup.checkForUpdate()
            }
            if !usesReviewProfile { NSApp.activate(ignoringOtherApps: true) }
        } catch {
            NSLog("The browsing session could not be opened: %@", error.localizedDescription)
            NSApp.terminate(nil)
        }
    }

    private func finishLaunching(_ owner: BrowserSessionOwner) {
        browserReady = true
        let previous = owner.session.windows
        if previous.isEmpty { createWindow() } else { for state in previous { createWindow(restoring: state) } }
        if !pendingLaunchURLs.isEmpty {
            let urls = pendingLaunchURLs
            pendingLaunchURLs.removeAll()
            openURLs(urls)
        }
        owner.startMaintenance()
        do {
            cliServer = try BrowserCLIServer(directory: owner.persistence.directory) { [weak self, weak owner] arguments in
                guard let self, let owner, !self.preparingQuit else {
                    return BrowserCLIResponse(error: "Browser is closing.")
                }
                return BrowserCLICommands.execute(arguments, owner: owner, store: self.store)
            }
        } catch {
            NSLog("The Browser CLI could not start: %@", error.localizedDescription)
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .scrollWheel,
        ]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let window = event.window, let context = self?.context(for: window) else { return false }
                if event.type == .scrollWheel { return context.handleSpaceScroll(event) == nil }
                context.handleSidebarPointer(event)
                return false
            }
            return consumed ? nil : event
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.store?.handleKeyboard(event) ?? false }
            return consumed ? nil : event
        }
    }

    func createWindow(restoring state: BrowserWindowState? = nil) {
        guard browserReady, let owner else { return }
        let store = owner.makeStore(restoring: state)
        owner.prewarmContentBlocking(in: store.activeSpace.id)
        let setupWindow = startupWindow
        let window = setupWindow ?? makeWindow(restoring: state)
        startupWindow = nil
        windows[store.id] = window
        store.window = window
        window.store = store
        store.isFullScreen = window.styleMask.contains(.fullScreen)
        let content = NSHostingView(rootView: BrowserRoot(store: store))
        content.safeAreaRegions = []
        window.contentView = content
        window.contentView?.superview?.clipsToBounds = true
        if !store.isFullScreen { owner.setWindowFrame(store.id, frame: window.frame) }
        if setupWindow == nil { presentWindow(window) }
        owner.activeWindowID = store.id
        owner.changed()
    }

    private func showStartup(_ phase: BrowserContentStartup.Phase) {
        let setup = BrowserContentStartupView(phase: phase)
        if let content = startupWindow?.contentView as? NSHostingView<BrowserContentStartupView> {
            content.rootView = setup
            return
        }
        let window = makeWindow(restoring: owner?.session.windows.first)
        let content = NSHostingView(rootView: setup)
        content.safeAreaRegions = []
        window.contentView = content
        window.contentView?.superview?.clipsToBounds = true
        startupWindow = window
        presentWindow(window)
    }

    private func makeWindow(restoring state: BrowserWindowState?) -> BrowserWindow {
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Browser"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        if let value = state?.frame, let frame = Optional(NSRectFromString(value)),
            NSScreen.screens.contains(where: {
                let visible = $0.visibleFrame.intersection(frame)
                return visible.width >= 100 && visible.height >= 100
            })
        {
            window.setFrame(frame, display: false)
        } else {
            window.center()
            if !windows.isEmpty {
                window.cascadeTopLeft(from: NSPoint(x: window.frame.minX + 24, y: window.frame.maxY - 24))
            }
        }
        return window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        if !browserReady { presentWindow(startupWindow) }
        else if !visible { createWindow() } else { presentWindow(window) }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard browserReady else {
            pendingLaunchURLs.append(contentsOf: urls)
            return
        }
        openURLs(urls)
    }

    private func openURLs(_ urls: [URL]) {
        if store == nil { createWindow() }
        presentWindow(window)
        let urls = urls.filter { ["http", "https", "file"].contains($0.scheme ?? "") }
        guard let store, store.canChangeTabCount(by: urls.count, in: store.activeSpace.id) else { return }
        for url in urls { store.open(url) }
    }

    private func presentWindow(_ window: NSWindow?) {
        guard let window else { return }
        if usesReviewProfile && !NSApp.isActive {
            if !window.isVisible { window.orderBack(nil) }
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !preparingQuit else { return .terminateCancel }
        guard browserReady, let owner else { return .terminateNow }
        preparingQuit = true
        Task {
            let allowed = await owner.canCloseAll()
            if allowed {
                owner.discardPrivatePartialDownloads()
            } else {
                preparingQuit = false
            }
            NSApp.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        cliServer?.stop()
        launchTask?.cancel()
        owner?.media?.stop()
        if browserReady { owner?.flush() }
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    private func context(for window: NSWindow) -> BrowserStore? {
        guard let id = windows.first(where: { $0.value === window })?.key else { return nil }
        return owner?.contexts[id]
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === startupWindow {
            NSApp.terminate(nil)
            return false
        }
        guard let context = context(for: sender) else { return true }
        if approvedCloses.remove(context.id) != nil { return true }
        guard preparingCloses.insert(context.id).inserted else { return false }
        Task {
            defer { preparingCloses.remove(context.id) }
            guard await context.canCloseWindow(isLastWindow: { self.windows.count == 1 }) else { return }
            approvedCloses.insert(context.id)
            sender.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let context = context(for: window) else { return }
        windows[context.id] = nil
        context.closeWindow()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let context = context(for: window) else { return }
        owner?.activeWindowID = context.id
        for page in context.visiblePages {
            page.owner = context
            page.hostingWindowID = context.id
            page.lastSelected = Date()
        }
        owner?.runtimeRevision &+= 1
    }
    func windowDidResize(_ notification: Notification) { rememberFrame(notification) }
    func windowDidMove(_ notification: Notification) { rememberFrame(notification) }
    private func rememberFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let context = context(for: window),
            !window.styleMask.contains(.fullScreen)
        else { return }
        owner?.setWindowFrame(context.id, frame: window.frame)
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        (notification.object as? NSWindow).flatMap(context(for:))?.isFullScreen = true
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        NotificationCenter.default.post(name: BrowserNativeWindowControlsHostView.fullScreenEntryFailed, object: window)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        (notification.object as? NSWindow).flatMap(context(for:))?.isFullScreen = false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let id = (info["tabID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let identifier = info["identifier"] as? String
        let generation = info["generation"] as? Int
        await openNotification(id: id, identifier: identifier, generation: generation)
    }
    private func openNotification(id: UUID, identifier: String?, generation: Int?) {
        guard let owner, let page = owner.pages[id] else { return }
        if let context = owner.contexts.values.first(where: { !$0.isClosed && $0.tabIndex(id) != nil }) {
            context.selectTab(id)
            windows[context.id]?.makeKeyAndOrderFront(nil)
        } else {
            createWindow(restoring: BrowserWindowState(spaceID: page.spaceID))
            store?.selectTab(id)
        }
        if let identifier, let generation {
            page.siteController?.send(
                ["type": "event", "identifier": identifier, "event": "click"], to: nil, generation: generation,
                bridge: "__browserHostedNotificationBridge")
        }
    }

}
