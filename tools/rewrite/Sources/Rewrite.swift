import AppKit

@main
@MainActor
final class Rewrite: NSObject, NSApplicationDelegate {
    private let shortcut = GlobalShortcut()
    private let settings = Settings()
    private let processor = ProcessorService()
    private let menuBar = MenuBarStatus()
    private var selection: CapturedSelection?
    private var task: Task<Void, Never>?
    private var warmup: Task<Void, Never>?
    private var generation = UUID()
    private var actionMenu: NSMenu?
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
            if event.keyCode == 53 { MainActor.assumeIsolated { if self?.task != nil { self?.cancel() } } }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 && self?.task != nil { self?.cancel() }
            return event
        }
        menuBar.onRewrite = { [weak self] in self?.begin() }
        menuBar.onCancel = { [weak self] in self?.cancel() }
        menuBar.onSettings = { [weak self] in self?.showSettings() }
        shortcut.onPress = { [weak self] in self?.begin() }
        settings.onShortcut = { [weak self] value in
            guard let self, self.shortcut.register(value) else { return false }
            self.menuBar.shortcutLabel = value.label; return true
        }
        settings.onSave = { [weak self] in self?.selection?.restoreFocus(); self?.selection = nil; self?.warmPi() }
        menuBar.shortcutLabel = settings.shortcut.label
        if !shortcut.register(settings.shortcut) { menuBar.showError("The shortcut is already in use. Choose another in Rewrite Settings.") }
        else if !settings.isConfigured { settings.show() }
        warmPi()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        warmup?.cancel(); task?.cancel(); processor.cancel(); processor.shutdown(); menuBar.remove()
    }

    private func warmPi() {
        guard settings.isConfigured else { return }
        let previous = warmup
        previous?.cancel()
        let configuration = settings.configuration
        warmup = Task { @MainActor in
            // Serialize configuration changes with any startup still in progress.
            await previous?.value
            guard !Task.isCancelled else { return }
            // Missing sign-in is reported on an actual rewrite, not during launch.
            try? await processor.warmUp(configuration)
        }
    }

    @objc private func begin() {
        if task != nil || selection != nil { cancel(); return }
        do {
            selection = try CapturedSelection.capture()
            guard settings.isConfigured else { settings.show(); return }
            guard let selection else { return }
            let actions = ActionMenu()
            actions.onChoose = { [weak self] action in self?.run(action) }
            let menu = actions.menu
            actionMenu = menu
            let picked = withExtendedLifetime(actions) { menu.popUp(positioning: menu.items.first, at: selection.point, in: nil) }
            actionMenu = nil
            if !picked { cancel() }
        } catch { selection = nil; menuBar.showError(error.localizedDescription) }
    }
    private func run(_ action: EditAction) {
        guard let selection else { return }
        let configuration = settings.configuration
        let current = UUID(); generation = current
        menuBar.setRewriting(action)
        // Leave the action menu before starting the request; the source app keeps focus.
        task = Task { @MainActor in
            await Task.yield()
            guard generation == current else { return }
            do {
                await warmup?.value
                try Task.checkCancellation()
                let output = try await processor.rewrite(selection.text, action: action, configuration: configuration)
                try Task.checkCancellation(); guard generation == current else { return }
                try await selection.replace(with: output, requireForeground: true)
                guard generation == current else { return }
                task = nil; cancel()
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                task = nil; self.selection = nil
                menuBar.showError(error.localizedDescription)
            }
        }
    }
    private func cancel() {
        menuBar.setRewriting(nil)
        generation = UUID(); task?.cancel(); task = nil
        actionMenu?.cancelTracking()
        selection?.restoreFocus(); selection = nil
    }
    @objc private func showSettings() { cancel(); settings.show() }
}
