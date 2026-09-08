import AppKit

@main
@MainActor
final class Rewrite: NSObject, NSApplicationDelegate {
    private let shortcut = GlobalShortcut()
    private let settings = Settings()
    private let processor = PiService()
    private let menuBar = MenuBarStatus()
    private lazy var controller = RewriteController(settings: settings, processor: processor, menuBar: menuBar)
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?

    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared, owner = Rewrite()
        app.delegate = owner
        // A Dock presence lets accessibility automation address the app during review.
        // It changes no selection, processing, or replacement behavior.
        app.setActivationPolicy(CommandLine.arguments.contains("--review") ? .regular : .accessory)
        let mainMenu = NSMenu(), appMenu = NSMenu(), editMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        app.mainMenu = mainMenu
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
        menuBar.onSettings = { [weak self] in self?.controller.showSettings() }
        shortcut.onPress = { [weak self] in self?.controller.begin() }
        settings.onShortcut = { [weak self] value in
            guard let self, self.shortcut.register(value) else { return false }
            self.menuBar.shortcutLabel = value.label; return true
        }
        settings.onSave = { [weak self] in self?.controller.settingsSaved() }
        menuBar.shortcutLabel = settings.shortcut.label
        if !shortcut.register(settings.shortcut) { menuBar.showError("The shortcut is already in use. Choose another in Rewrite Settings.") }
        else if !settings.isConfigured { settings.show() }
        warmPi()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        controller.cancel(); processor.shutdown(); menuBar.remove()
    }

    private func warmPi() {
        guard settings.isConfigured else { return }
        processor.warmUp(settings.configuration)
    }

}
