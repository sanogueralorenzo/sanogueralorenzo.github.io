/// Setup finished, and opened the guide in `guide` when the core asked.
struct BrowserSetupCompleted: BrowserSetupFinishResult {
    // MARK: - Variables

    let guide: BrowserTabRuntimeAssignment?

    // MARK: - Actions - Finishing

    @MainActor
    func apply(to receiver: some BrowserSetupFinishReceiver) {
        receiver.setupCompleted(guide: guide)
    }
}
