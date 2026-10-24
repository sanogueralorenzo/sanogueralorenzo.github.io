import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    var isRevealedByPointer = false
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.isRevealedByPointer = isRevealedByPointer
        view.schedulePointerRefresh()
    }
}
