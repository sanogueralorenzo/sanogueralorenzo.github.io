import AppKit

@main
@MainActor
final class Rewrite: NSObject, NSApplicationDelegate {
    private let shortcut = AppShortcut()
    private let processor = PiService()
    private let menuBar = AppMenu()
    private lazy var controller = RewriteController(processor: processor, menuBar: menuBar)
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?

    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared, owner = Rewrite()
        app.delegate = owner
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { if self?.controller.isRewriting == true { self?.controller.cancel() } } }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && self?.controller.isRewriting == true { self?.controller.cancel() }
            return event
        }
        menuBar.onRewrite = { [weak self] in self?.controller.begin() }
        menuBar.onCancel = { [weak self] in self?.controller.cancel() }
        menuBar.setProvider(controller.provider)
        menuBar.onProvider = { [weak self] provider in self?.controller.selectProvider(provider) }
        shortcut.onPress = { [weak self] in self?.controller.begin() }
        if !shortcut.register() { menuBar.showError("Could not register ⌥R. Use Rewrite in the pencil menu, or free ⌥R in the other app and restart Rewrite.") }
        processor.warmUp(controller.provider)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        controller.cancel(); processor.shutdown(); menuBar.remove()
    }

}
