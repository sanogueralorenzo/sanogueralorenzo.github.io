import SwiftUI

/// Adds the Mac window server's pointer tracking to the shared collapsed-edge
/// reveal control without taking any input away from the page underneath it.
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
