import SwiftUI

struct BrowserCollapsedSidebarHoverTracker: NSViewRepresentable {
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(
        context: Context
    ) -> BrowserCollapsedSidebarHoverTrackingView {
        BrowserCollapsedSidebarHoverTrackingView(
            onHoverChange: onHoverChange
        )
    }

    func updateNSView(
        _ nsView: BrowserCollapsedSidebarHoverTrackingView,
        context: Context
    ) {
        nsView.onHoverChange = onHoverChange
    }
}
