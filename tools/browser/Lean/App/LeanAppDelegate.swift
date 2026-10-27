import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class LeanAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var owner: BrowserSessionOwner?
    var windows: [UUID: NSWindow] = [:]
    private var approvedCloses: Set<UUID> = []
    private var preparingCloses: Set<UUID> = []
    private var preparingQuit = false
    private var pointerMonitor: Any?
    private var keyboardMonitor: Any?
    var store: BrowserStore? {
        guard let owner else { return nil }
        return owner.activeWindowID.flatMap { owner.contexts[$0] } ?? owner.contexts.values.first { !$0.isClosed }
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
            installMenu()
            let previous = owner.session.windows.filter(\.isOpen)
            if previous.isEmpty { createWindow() } else { for state in previous { createWindow(restoring: state) } }
            owner.startMaintenance()
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .mouseMoved, .leftMouseDown, .leftMouseUp, .swipe,
            ]) { [weak self] event in
                MainActor.assumeIsolated {
                    if let window = event.window { self?.context(for: window)?.handleSidebarPointer(event) }
                }
                return event
            }
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
                [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.store?.handleKeyboard(event) ?? false }
                return consumed ? nil : event
            }
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The browsing session could not be opened"
            alert.informativeText = error.localizedDescription + " Your existing files have been preserved."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func createWindow(restoring state: BrowserWindowState? = nil) {
        guard let owner else { return }
        let store = owner.makeStore(restoring: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        windows[store.id] = window
        store.window = window
        window.title = "Lean"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.minSize = NSSize(width: 700, height: 480)
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: BrowserRoot(store: store))
        window.contentView?.superview?.clipsToBounds = true
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
            if windows.count > 1 {
                window.cascadeTopLeft(from: NSPoint(x: window.frame.minX + 24, y: window.frame.maxY - 24))
            }
        }
        window.makeKeyAndOrderFront(nil)
        owner.activeWindowID = store.id
        owner.changed()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
        if !visible { createWindow() } else { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if store == nil { createWindow() }
        for url in urls where ["http", "https", "file"].contains(url.scheme ?? "") { store?.open(url) }
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !preparingQuit else { return .terminateCancel }
        guard let owner else { return .terminateNow }
        preparingQuit = true
        Task {
            let allowed = await owner.canCloseAll()
            if !allowed { preparingQuit = false }
            NSApp.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        owner?.media?.stop()
        owner?.flush()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    private func context(for window: NSWindow) -> BrowserStore? {
        guard let id = windows.first(where: { $0.value === window })?.key else { return nil }
        return owner?.contexts[id]
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let context = context(for: sender) else { return true }
        if approvedCloses.remove(context.id) != nil { return true }
        guard preparingCloses.insert(context.id).inserted else { return false }
        Task {
            defer { preparingCloses.remove(context.id) }
            for page in context.visiblePages {
                guard await page.prepareToClose() else { return }
                await page.captureDocumentState()
            }
            if context.activeSpace.isPrivate,
                !owner!.contexts.values.contains(where: {
                    !$0.isClosed && $0.id != context.id && $0.activeSpace.id == context.activeSpace.id
                })
            {
                guard await context.prepareToDeleteSpace(context.activeSpace.id) else { return }
            }
            if windows.count == 1 && !context.activeDownloads.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Downloads are still running"
                alert.informativeText = "They will continue while Lean is open."
                alert.addButton(withTitle: "Keep Window Open")
                alert.addButton(withTitle: "Close Window")
                guard await BrowserDialogs.ask(alert, in: sender) == .alertSecondButtonReturn else { return }
            }
            guard context.flush() else {
                context.showNotice("The session could not be saved.")
                return
            }
            approvedCloses.insert(context.id)
            sender.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let context = context(for: window) else { return }
        context.isClosed = true
        context.windowState.isOpen = false
        for page in context.visiblePages where page.hostingWindowID == context.id { page.hostingWindowID = nil }
        windows[context.id] = nil
        if context.activeSpace.isPrivate
            && !owner!.contexts.values.contains(where: { !$0.isClosed && $0.activeSpace.id == context.activeSpace.id })
        {
            context.deleteSpace(context.activeSpace.id, prepared: true)
        }
        context.changed()
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
                bridge: "__leanHostedNotificationBridge")
        }
    }

}
