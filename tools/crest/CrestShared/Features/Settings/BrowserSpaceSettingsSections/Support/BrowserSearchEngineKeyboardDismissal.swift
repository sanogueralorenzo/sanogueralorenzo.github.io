import Foundation

/// Keeps deferred keyboard work within the lifetime of its owning settings screen.
@MainActor
final class BrowserSearchEngineKeyboardDismissal {
    private let delay: Duration?
    private let sleep: @MainActor (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        delay: Duration? = BrowserPlatformSearchEnginePresentation.keyboardDismissalDelay,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    isolated deinit { task?.cancel() }

    func schedule(_ dismissKeyboard: @escaping @MainActor () -> Void) {
        cancel()
        guard let delay else { return }
        task = Task { [sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dismissKeyboard()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
