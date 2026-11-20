import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    let waitsForPointer: Bool
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.waitsForPointer = waitsForPointer
        view.schedulePointerRefresh()
    }
}
