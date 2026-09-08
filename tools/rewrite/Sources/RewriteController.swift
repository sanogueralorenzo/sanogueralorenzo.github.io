import AppKit

@MainActor
final class RewriteController {
    private(set) var provider = RewriteProvider.load()
    private let processor: PiService
    private let menuBar: MenuBarStatus
    private var selection: CapturedSelection?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var actionMenu: NSMenu?
    var isRewriting: Bool { task != nil }

    init(processor: PiService, menuBar: MenuBarStatus) {
        self.processor = processor; self.menuBar = menuBar
    }
    func selectProvider(_ provider: RewriteProvider) {
        guard self.provider != provider else { return }
        cancel()
        self.provider = provider; provider.save()
        processor.warmUp(provider)
    }
    func begin() {
        if task != nil || selection != nil { cancel(); return }
        do {
            selection = try CapturedSelection.capture()
            guard let selection else { return }
            let actions = ActionMenu()
            actions.onChoose = { [weak self] action in self?.run(action) }
            let menu = actions.menu
            actionMenu = menu
            let picked = withExtendedLifetime(actions) { menu.popUp(positioning: menu.items.first, at: selection.point, in: nil) }
            actionMenu = nil
            if !picked { cancel() }
        } catch {
            selection = nil
            if case RewriteError.accessibilityPermission = error {
                menuBar.showError(error.localizedDescription, opensPermissions: true)
            } else { menuBar.showError(error.localizedDescription) }
        }
    }
    private func run(_ action: EditAction) {
        guard let selection else { return }
        let provider = provider
        let current = UUID(); generation = current
        menuBar.setRewriting(action)
        // Leave the action menu before starting the request; the source app keeps focus.
        task = Task { @MainActor in
            await Task.yield()
            guard generation == current else { return }
            do {
                let output = try await processor.rewrite(selection.text, action: action, provider: provider)
                try Task.checkCancellation(); guard generation == current else { return }
                try RewriteClipboard.copy(output)
                task = nil; self.selection = nil
                menuBar.setRewriting(nil)
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
        selection = nil
    }
}
