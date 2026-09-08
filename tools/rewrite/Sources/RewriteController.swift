import AppKit

@MainActor
final class RewriteController {
    private(set) var provider = RewriteProvider.load()
    private let processor: PiService
    private let menuBar: MenuBarStatus
    private var task: Task<Void, Never>?
    private var generation = UUID()
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
        if task != nil { cancel(); return }
        let selection: CapturedSelection
        do { selection = try CapturedSelection.capture() }
        catch {
            if case RewriteError.accessibilityPermission = error {
                menuBar.showError(error.localizedDescription, opensPermissions: true)
            } else { menuBar.showError(error.localizedDescription) }
            return
        }
        let provider = provider
        let current = UUID(); generation = current
        menuBar.setRewriting(true)
        // Let a menu click finish before starting the request.
        task = Task { @MainActor in
            await Task.yield()
            guard generation == current else { return }
            do {
                let output = try await processor.rewrite(selection.text, provider: provider)
                try Task.checkCancellation(); guard generation == current else { return }
                try RewriteClipboard.copy(output)
                task = nil
                menuBar.setRewriting(false)
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                task = nil
                menuBar.showError(error.localizedDescription)
            }
        }
    }
    func cancel() {
        menuBar.setRewriting(false)
        generation = UUID()
        if task != nil { task?.cancel(); processor.cancel() }
        task = nil
    }
}
