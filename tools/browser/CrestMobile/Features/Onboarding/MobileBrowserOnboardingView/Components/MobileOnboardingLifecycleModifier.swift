import SwiftUI

struct MobileOnboardingLifecycleModifier: ViewModifier {
    let request: BrowserOnboardingRequest
    /// Starts what the onboarding shows once it appears, since a view may be
    /// built more than once.
    let appeared: () -> Void
    let requestChanged: (BrowserOnboardingRequest) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: appeared)
            .onChange(of: request) { _, request in
                requestChanged(request)
            }
            .interactiveDismissDisabled(request.entryPoint == .firstRun)
    }
}
