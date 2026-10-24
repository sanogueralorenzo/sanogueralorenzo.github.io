/// How finishing setup came out. Each outcome tells the window that finished
/// setup what happened, through the one method of `BrowserSetupFinishReceiver`
/// it stands for, so a window's whole handling is `result.apply(to: …)`.
protocol BrowserSetupFinishResult: Sendable {
    @MainActor
    func apply(to receiver: some BrowserSetupFinishReceiver)
}

/// A window that finishes setup, and what it does with each outcome.
@MainActor
protocol BrowserSetupFinishReceiver {
    /// Setup finished, and opened the guide in `guide` when the core asked.
    func setupCompleted(guide: BrowserTabRuntimeAssignment?)
    /// The person did not unlock the guide's Space, or the task went.
    func setupCancelled()
    /// The core refused to finish, in its own words.
    func setupRefused(_ message: String)
}
