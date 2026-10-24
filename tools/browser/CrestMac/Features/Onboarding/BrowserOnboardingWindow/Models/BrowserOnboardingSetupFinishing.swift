/// What finishing setup from the onboarding window does with each outcome:
/// a finished setup is recorded and the window goes on, and a refusal shows
/// on the flow.
@MainActor
struct BrowserOnboardingSetupFinishing: BrowserSetupFinishReceiver {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    let progress: BrowserOnboardingProgressStore
    let onCompleted: @MainActor () -> Void

    // MARK: - Actions - Finishing

    func setupCompleted(guide _: BrowserTabRuntimeAssignment?) {
        progress.setupFinished()
        onCompleted()
    }

    func setupCancelled() {}

    func setupRefused(_ message: String) {
        flow.completionFailure = message
    }
}
