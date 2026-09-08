import AppKit

@MainActor
final class RewriteController {
    private(set) var provider: RewriteProvider
    private let processor: PiService
    private let menuBar: AppMenu
    private let captureText: @MainActor () throws -> String
    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var isRewriting: Bool { task != nil && task?.isCancelled == false }

    init(processor: PiService, menuBar: AppMenu, defaults: UserDefaults = .standard,
         pasteboard: NSPasteboard = .general, captureText: @escaping @MainActor () throws -> String = SelectedText.read) {
        self.processor = processor; self.menuBar = menuBar
        self.defaults = defaults; self.pasteboard = pasteboard; self.captureText = captureText
        provider = RewriteProvider.load(from: defaults)
    }
    func selectProvider(_ provider: RewriteProvider) {
        guard self.provider != provider else { return }
        cancel()
        self.provider = provider; provider.save(to: defaults)
        processor.warmUp(provider)
    }
    func begin() {
        if isRewriting { cancel(); return }
        let text: String
        do { text = try captureText() }
        catch {
            if case RewriteError.accessibilityPermission = error {
                menuBar.showError(error.localizedDescription, opensPermissions: true)
            } else { menuBar.showError(error.localizedDescription) }
            return
        }
        let provider = provider
        let current = UUID(); generation = current
        menuBar.setRewriting(true)
        let previous = task
        // Finish cancellation cleanup before letting the next request use Pi.
        task = Task { @MainActor in
            await previous?.value
            await Task.yield()
            guard generation == current else { return }
            do {
                let output = try await processor.rewrite(text, provider: provider)
                try Task.checkCancellation(); guard generation == current else { return }
                try RewriteClipboard.copy(output, to: pasteboard)
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
        // Retain the cancelled task so the next rewrite can await its cleanup.
    }
}
