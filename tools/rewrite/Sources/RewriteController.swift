import AppKit

@MainActor
final class RewriteController {
    private let settings: Settings
    private let processor: PiService
    private let menuBar: MenuBarStatus
    private var selection: CapturedSelection?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var actionMenu: NSMenu?
    var isRewriting: Bool { task != nil }

    init(settings: Settings, processor: PiService, menuBar: MenuBarStatus) {
        self.settings = settings; self.processor = processor; self.menuBar = menuBar
    }
    func settingsSaved() {
        selection?.restoreFocus(); selection = nil
        processor.warmUp(settings.configuration)
    }
    func begin() {
        if task != nil || selection != nil { cancel(); return }
        do {
            selection = try CapturedSelection.capture()
            try selection?.validateForRewrite()
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
                let output = try await processor.rewrite(selection.text, action: action, configuration: configuration) {
                    try selection.validateForRewrite()
                }
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
    func cancel() {
        menuBar.setRewriting(nil)
        generation = UUID()
        if task != nil { task?.cancel(); processor.cancel() }
        task = nil
        actionMenu?.cancelTracking()
        selection?.restoreFocus(); selection = nil
    }
    func showSettings() { cancel(); settings.show() }
}
