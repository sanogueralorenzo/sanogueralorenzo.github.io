/// The person did not unlock the guide's Space, or the task went.
struct BrowserSetupCancelled: BrowserSetupFinishResult {
    // MARK: - Actions - Finishing

    @MainActor
    func apply(to receiver: some BrowserSetupFinishReceiver) {
        receiver.setupCancelled()
    }
}
