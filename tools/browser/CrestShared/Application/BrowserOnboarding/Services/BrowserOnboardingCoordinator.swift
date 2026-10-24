import Observation

@Observable
@MainActor
final class BrowserOnboardingCoordinator {
    var request: BrowserOnboardingRequest = .firstRun
    var isMobilePresented = false

    func presentOnMobile(_ request: BrowserOnboardingRequest) {
        self.request = request
        isMobilePresented = true
    }
}
