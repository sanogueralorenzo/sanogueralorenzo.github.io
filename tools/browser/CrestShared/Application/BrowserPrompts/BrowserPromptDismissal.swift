import Foundation

/// Closes what the presenters show for a question once the question no longer
/// waits: the engine withdrew it, its page went, or it was answered. Each
/// presenter attaches how to close what it shows; one that attaches after the
/// dismissal closes at once. What closes this way answers as declined, which
/// the core refuses for a question that no longer waits.
@MainActor
final class BrowserPromptDismissal {
    // MARK: - Variables

    private var closers: [() -> Void] = []
    private(set) var isDismissed = false

    // MARK: - Actions - Presenting

    /// How a presenter closes what it shows for the question.
    func attach(_ close: @escaping () -> Void) {
        if isDismissed {
            close()
        } else {
            closers.append(close)
        }
    }

    /// The question no longer waits.
    func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        let closers = closers
        self.closers = []
        for close in closers { close() }
    }
}
