import AppKit
import Carbon
import SwiftUI
import UserNotifications

@main
@MainActor
final class Minutes: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var model: MinutesModel!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var recordItem: NSMenuItem!
    private var providerItems: [NSMenuItem] = []
    private var hotKey: EventHotKeyRef?
    private var timer: Timer?
    static func main() {
        umask(0o077)
        let app = NSApplication.shared
        let delegate = Minutes(); app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let standard = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Minutes")
        let args = CommandLine.arguments
        let review = args.contains("--review")
        var support = standard
        if review {
            guard let i = args.firstIndex(of: "--data-dir"), args.indices.contains(i + 1), args[i + 1].hasPrefix("/") else { fail("Review mode requires --data-dir /absolute/path."); return }
            support = URL(fileURLWithPath: args[i + 1])
            guard support.resolvingSymlinksInPath().standardizedFileURL != standard.resolvingSymlinksInPath().standardizedFileURL else { fail("Use a separate review profile."); return }
        }
        do { model = try MinutesModel(root: support.appendingPathComponent("meetings"), support: support, review: review) }
        catch { fail(error.localizedDescription); return }
        UNUserNotificationCenter.current().delegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 530), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Minutes"; window.isReleasedWhenClosed = false; window.center()
        window.contentView = NSHostingView(rootView: MinutesView(model: model))
        let mainMenu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        appMenu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        let editMenu = NSMenu(title: "Edit"); let editItem = NSMenuItem(); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        recordItem = menu.addItem(withTitle: "Start recording    ⌥⇧M", action: #selector(toggleRecording), keyEquivalent: ""); recordItem.target = self
        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "Recent meetings", action: #selector(showWindow), keyEquivalent: ""); open.target = self
        let providers = NSMenu(); providers.autoenablesItems = false
        for choice in Provider.allCases {
            let item = providers.addItem(withTitle: choice.label, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = choice; providerItems.append(item)
        }
        providers.addItem(.separator())
        let info = providers.addItem(withTitle: "Transcripts are sent through Pi", action: nil, keyEquivalent: ""); info.isEnabled = false
        menu.addItem(withTitle: "Provider", action: nil, keyEquivalent: "").submenu = providers
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        model.changed = { [weak self] in self?.updateStatus() }
        model.openWindow = { [weak self] in self?.showWindow() }
        installShortcut()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.model.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        model.tick(); showWindow()
    }
    private func fail(_ text: String) { let alert = NSAlert(); alert.messageText = "Minutes could not open"; alert.informativeText = text; alert.runModal(); NSApp.terminate(nil) }
    @objc private func toggleRecording() { model.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func selectProvider(_ sender: NSMenuItem) { if let provider = sender.representedObject as? Provider { model.selectProvider(provider) } }
    @objc private func showWindow() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc private func willSleep() {
        if model.activity.recordingID != nil { Task { await model.stop(captureFailure: "Recording ended because the Mac went to sleep. Retry to process the saved audio.") } }
    }
    private func updateStatus() {
        let recording = model.activity.recordingID != nil
        let processing = model.activity.showsProgress
        statusItem.button?.image = NSImage(systemSymbolName: recording ? "record.circle.fill" : (processing ? "ellipsis.circle" : "waveform"), accessibilityDescription: model.status)
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
        statusItem.button?.title = recording ? " " + model.elapsed : ""
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.toolTip = model.status
        recordItem.title = recording ? "Stop recording    ⌥⇧M" : (processing ? "Processing…" : "Start recording    ⌥⇧M")
        recordItem.isEnabled = !processing
        for item in providerItems {
            item.state = item.representedObject as? Provider == model.provider ? .on : .off
            item.isEnabled = !model.isWorking
        }
    }
    private func installShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, pointer in
            guard let pointer else { return noErr }
            let owner = Unmanaged<Minutes>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated { owner.model.toggle() }
            return noErr
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey | shiftKey), EventHotKeyID(signature: 0x4D494E53, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if installed != noErr || registered != noErr { model.error = "Could not register ⌥⇧M. Another app may use it; use Record in Minutes instead." }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil, model.isWorking else { return .terminateNow }
        showWindow()
        let alert = NSAlert()
        alert.messageText = model.activity.recordingID != nil ? "Stop recording before quitting" : "Minutes is still working"
        alert.informativeText = "Close the window to leave Minutes running in the menu bar. Your audio and transcript stay saved."
        if model.activity.recordingID != nil { alert.addButton(withTitle: "Stop and finish note"); alert.addButton(withTitle: "Keep recording"); if alert.runModal() == .alertFirstButtonReturn { model.toggle() } }
        else { alert.addButton(withTitle: "Keep processing"); alert.runModal() }
        return .terminateCancel
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["meeting"] as? String
        Task { @MainActor in if let id { model.selected = UUID(uuidString: id) }; showWindow() }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner]) }
}
