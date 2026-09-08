import AppKit
import Carbon.HIToolbox
import ServiceManagement

@main
@MainActor
final class Clipboard: NSObject, NSApplicationDelegate {
    private lazy var menu = ClipboardMenu()
    private let preview = ClipboardPreview()
    private var store: ClipboardStore!
    private var policy = ClipboardPolicy()
    private var historyAvailable = false
    private var changeCount = NSPasteboard.general.changeCount
    private var shortcutError: String?
    private var hotKey: EventHotKeyRef?

    static func main() {
        let app = NSApplication.shared
        let delegate = Clipboard()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        preview.nextResponder = NSApp.nextResponder; NSApp.nextResponder = preview
        preview.onError = { [weak self] in self?.report($0) }
        preview.clear()
        menu.onOpen = { [weak self] in
            guard let self else { return }
            self.store?.prune()
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self.capture(source: app)
            }
        }
        menu.onCopy = { [weak self] in self?.restore($0) }
        menu.onSpace = { [weak self] clip in
            if let url = clip.webURL {
                if !NSWorkspace.shared.open(url) { self?.report("The link could not be opened.") }
            } else { self?.preview.show(clip) }
        }
        menu.onClear = { [weak self] in
            guard let self, self.historyAvailable else { return }
            self.menu.report(self.shortcutError)
            self.changeCount = NSPasteboard.general.clearContents()
            self.store.clear()
        }
        installShortcut()
        menu.onRetentionChange = { [weak self] in self?.store?.setRetention(days: $0) }
        let standard = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clipboard")
        let args = CommandLine.arguments
        let review = args.contains("--review")
        var directory = standard
        if review {
            guard let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1), args[index + 1].hasPrefix("/") else {
                report("Review mode requires --data-dir /absolute/path to a separate profile."); return
            }
            directory = URL(fileURLWithPath: args[index + 1])
            guard directory.resolvingSymlinksInPath().standardizedFileURL != standard.resolvingSymlinksInPath().standardizedFileURL else {
                report("Review mode requires a separate profile."); return
            }
        }
        if !review { registerAtLogin() }
        store = ClipboardStore(directory: directory, review: review)
        store.onChange = { [weak self] clips, policy, error, available in
            guard let self else { return }
            self.policy = policy; self.historyAvailable = available
            if let error { self.report(error) }
            self.menu.update(clips: clips, retentionDays: policy.retentionDays)
        }
        store.load()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.capture() } }
        RunLoop.main.add(timer, forMode: .common)
        let expiryTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.store?.prune() } }
        expiryTimer.tolerance = 5
        RunLoop.main.add(expiryTimer, forMode: .common)
        _ = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.capture(source: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if historyAvailable { capture(); store.finishWrites() }
        preview.clear()
    }
    private func capture(source: NSRunningApplication? = nil) {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        let source = source ?? NSWorkspace.shared.frontmostApplication
        guard historyAvailable, source?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !policy.excludedAppIds.contains(source?.bundleIdentifier ?? "") else { return }
        do {
            if let snapshot = try ClipboardSupport.snapshot(pb, source: source) {
                store.capture { try ClipboardSupport.prepare(snapshot) }
            }
        }
        catch { report(error.localizedDescription) }
    }
    private func restore(_ clip: Clip) {
        do {
            try ClipboardSupport.restore(clip, to: .general)
            changeCount = NSPasteboard.general.changeCount
            menu.dismiss()
        } catch { report(error.localizedDescription) }
    }
    private func report(_ text: String) { menu.report(text) }
    private func registerAtLogin() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "loginRegistrationComplete") else { return }
        do {
            let service = SMAppService.mainApp
            if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            defaults.set(true, forKey: "loginRegistrationComplete")
            if service.status == .requiresApproval {
                report("Enable Clipboard in System Settings → General → Login Items to start it automatically.")
            }
        } catch { report("Could not enable launch at login: \(error.localizedDescription)") }
    }
    private func installShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, pointer in
            guard let pointer else { return noErr }
            let owner = Unmanaged<Clipboard>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated { owner.menu.show() }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(optionKey), EventHotKeyID(signature: 0x434C4950, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr || registered != noErr {
            shortcutError = "Could not register ⌥C (\(status != noErr ? status : registered)). Open Clipboard from its menu bar icon."
            report(shortcutError!)
        }
    }
}
