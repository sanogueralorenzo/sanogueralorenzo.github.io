import AppKit

@main
@MainActor
final class Rewrite: NSObject, NSApplicationDelegate {
    private let shortcut = GlobalShortcut()
    private let preview = Preview()
    private let toolbar = SelectionToolbar()
    private let watcher = SelectionWatcher()
    private var toolbarSelection: CapturedSelection?
    private let settings = Settings()
    private let processor = ProcessorService()
    private var statusItem: NSStatusItem!
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
                self.task == nil && !self.preview.panel.isVisible && !self.settings.isVisible
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
        watcher.interactionWindow = toolbar.panel
        watcher.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Rewrite")
        let menu = NSMenu()
        for (title, action, key) in [("Rewrite Selection", #selector(begin), ""), ("Settings…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator()); let quit = NSMenuItem(title: "Quit Rewrite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(quit)
        statusItem.menu = menu
        shortcut.onPress = { [weak self] in self?.begin() }
        settings.onShortcut = { [weak self] value in
            guard let self, self.shortcut.register(value) else { return false }
            self.statusItem.button?.toolTip = "Rewrite · \(value.label)"; return true
        }
        preview.onCancel = { [weak self] in self?.cancel() }
        preview.onCopy = { [weak self] in self?.copy() }
        preview.onReplace = { [weak self] in self?.replace() }
        settings.onSave = { [weak self] in self?.selection?.restoreFocus(); self?.selection = nil }
        statusItem.button?.toolTip = "Rewrite · \(settings.shortcut.label)"
        if !shortcut.register(settings.shortcut) { preview.message("The shortcut is already in use. Choose another in Rewrite Settings.") }
        else if !settings.isConfigured { settings.show() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { watcher.stop(); toolbar.hide(); task?.cancel(); processor.cancel(); preview.close() }

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
        } catch { preview.message(error.localizedDescription) }
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
        // Leave the native menu's tracking loop before activating the preview.
        task = Task { @MainActor in
            await Task.yield()
            guard generation == current else { return }
            preview.processing(action: action, original: selection.text, point: selection.point, provider: configuration.kind.rawValue)
            do {
                let output = try await processor.rewrite(selection.text, action: action, configuration: configuration)
                try Task.checkCancellation(); guard generation == current else { return }
                result = output; task = nil
                preview.showResult(output, limitation: selection.replacementLimitation())
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                task = nil; preview.message(error.localizedDescription, at: selection.point)
            }
        }
    }
    private func cancel() {
        watcher.dismiss()
        generation = UUID(); task?.cancel(); task = nil; processor.cancel(); actionMenu?.cancelTracking()
        preview.close(); selection?.restoreFocus(); selection = nil; result = nil
    }
    private func copy() {
        guard let result else { return }
        // Copy is the only action that intentionally changes the clipboard.
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(result, forType: .string) else {
            preview.limitation("Could not write to the clipboard. Try Copy again."); return
        }
        cancel()
    }
    private func replace() {
        guard task == nil, let selection, let result else { return }
        let current = generation
        task = Task { @MainActor in
            do {
                try await selection.replace(with: result)
                guard generation == current else { return }
                task = nil; cancel()
            } catch {
                guard generation == current else { return }
                task = nil; preview.limitation(error.localizedDescription)
                NSApp.activate(ignoringOtherApps: true); preview.panel.makeKeyAndOrderFront(nil)
            }
        }
    }
    @objc private func showSettings() { cancel(); settings.show() }
}
