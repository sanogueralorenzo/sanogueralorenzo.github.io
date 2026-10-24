/// The core refused to finish, in its own words.
struct BrowserSetupRefused: BrowserSetupFinishResult {
    // MARK: - Variables

    let message: String

    // MARK: - Actions - Finishing

    @MainActor
    func apply(to receiver: some BrowserSetupFinishReceiver) {
        receiver.setupRefused(message)
    }
}
