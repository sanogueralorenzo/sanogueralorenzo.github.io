import AppKit

@main
@MainActor
final class Rewrite: NSObject, NSApplicationDelegate {
    private let shortcut = GlobalShortcut()
    private let notice = ResultNotice()
    private let toolbar = SelectionToolbar()
    private let watcher = SelectionWatcher()
    private var toolbarSelection: CapturedSelection?
    private let settings = Settings()
    private let processor = ProcessorService()
    private let menuBar = MenuBarStatus()
    private var selection: CapturedSelection?
    private var result: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var actionMenu: NSMenu?

    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared, owner = Rewrite()
        app.delegate = owner
        // A Dock presence lets accessibility automation address the app during review.
        // It changes no selection, processing, or replacement behavior.
        app.setActivationPolicy(CommandLine.arguments.contains("--review") ? .regular : .accessory)
        let mainMenu = NSMenu(), appMenu = NSMenu(), editMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        appMenu.addItem(withTitle: "Quit Rewrite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        app.mainMenu = mainMenu
        withExtendedLifetime(owner) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher.isEnabled = { [weak self] in
            guard let self else { return false }
            return self.settings.automaticToolbar && self.settings.isConfigured && self.selection == nil &&
                self.task == nil && !self.notice.panel.isVisible && !self.settings.isVisible
        }
        watcher.onSelection = { [weak self] selection in
            self?.toolbarSelection = selection; self?.toolbar.show(at: selection.point)
        }
        watcher.onHide = { [weak self] in self?.toolbar.hide(); self?.toolbarSelection = nil }
        toolbar.onDismiss = { [weak self] in self?.watcher.dismiss() }
        toolbar.onChoose = { [weak self] action in
            guard let self, let selected = self.toolbarSelection,
                  !selected.invalidated, let current = try? CapturedSelection.capture(), selected.matches(current) else {
                self?.watcher.dismiss(); return
            }
            self.selection = selected; self.watcher.dismiss(); self.run(action)
        }
        watcher.onEscape = { [weak self] in if self?.task != nil { self?.cancel() } }
        watcher.interactionWindow = toolbar.panel
        watcher.start()
        menuBar.onRewrite = { [weak self] in self?.begin() }
        menuBar.onCancel = { [weak self] in self?.cancel() }
        menuBar.onSettings = { [weak self] in self?.showSettings() }
        shortcut.onPress = { [weak self] in self?.begin() }
        settings.onShortcut = { [weak self] value in
            guard let self, self.shortcut.register(value) else { return false }
            self.menuBar.shortcutLabel = value.label; return true
        }
        notice.onClose = { [weak self] in self?.cancel() }
        notice.onCopy = { [weak self] in self?.copy() }
        settings.onSave = { [weak self] in self?.selection?.restoreFocus(); self?.selection = nil }
        menuBar.shortcutLabel = settings.shortcut.label
        if !shortcut.register(settings.shortcut) { notice.show("The shortcut is already in use. Choose another in Rewrite Settings.") }
        else if !settings.isConfigured { settings.show() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { watcher.stop(); toolbar.hide(); task?.cancel(); processor.cancel(); notice.closePanel() }

    @objc private func begin() {
        watcher.dismiss()
        if task != nil || selection != nil { cancel(); return }
        do {
            selection = try CapturedSelection.capture()
            guard settings.isConfigured else { settings.show(); return }
            guard let selection else { return }
            let menu = NSMenu(); menu.autoenablesItems = false
            for (index, action) in EditAction.allCases.prefix(3).enumerated() { menu.addItem(actionItem(action, index: index)) }
            let tone = NSMenuItem(title: "Change tone", action: nil, keyEquivalent: "")
            let tones = NSMenu()
            for (index, action) in EditAction.allCases.suffix(3).enumerated() { tones.addItem(actionItem(action, index: index + 3)) }
            tone.submenu = tones; menu.addItem(tone)
            actionMenu = menu
            let picked = menu.popUp(positioning: menu.items.first, at: selection.point, in: nil)
            actionMenu = nil
            if !picked { cancel() }
        } catch { notice.show(error.localizedDescription) }
    }
    private func actionItem(_ action: EditAction, index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: action.rawValue, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self; item.tag = index; return item
    }
    @objc private func choose(_ sender: NSMenuItem) {
        run(EditAction.allCases[sender.tag])
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
                let output = try await processor.rewrite(selection.text, action: action, configuration: configuration)
                try Task.checkCancellation(); guard generation == current else { return }
                result = output
                try await selection.replace(with: output, requireForeground: true)
                guard generation == current else { return }
                task = nil; cancel()
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                task = nil; menuBar.setRewriting(nil)
                notice.show(error.localizedDescription, result: result, at: selection.point)
            }
        }
    }
    private func cancel() {
        watcher.dismiss(); menuBar.setRewriting(nil)
        generation = UUID(); task?.cancel(); task = nil; processor.cancel(); actionMenu?.cancelTracking()
        notice.closePanel(); selection?.restoreFocus(); selection = nil; result = nil
    }
    private func copy() {
        guard let result else { return }
        // Copy is the only action that intentionally changes the clipboard.
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(result, forType: .string) else {
            notice.show("Could not write to the clipboard. Try Copy again.", result: result); return
        }
        cancel()
    }
    @objc private func showSettings() { cancel(); settings.show() }
}
