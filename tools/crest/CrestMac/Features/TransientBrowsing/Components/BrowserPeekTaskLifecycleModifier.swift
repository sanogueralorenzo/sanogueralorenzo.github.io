import SwiftUI

/// Presents a Peek's page once per request. The core records what the page's
/// navigations visit from its engine's reports.
struct BrowserPeekTaskLifecycleModifier: ViewModifier {
    let requestID: UUID
    let present: @MainActor @Sendable () async -> Void

    func body(content: Content) -> some View {
        content
            .task(id: requestID) {
                await present()
            }
    }
}
