import SwiftUI

/// Attaches AppKit hover tracking to one Split View card.
///
/// Placed as an overlay so the tracked region is the card's full bounds — web
/// content, find bar, failure overlay and all — and reports nothing but "the
/// pointer is inside this card". What that is worth is decided by
/// `BrowserSplitPageSurface.focusesOnHover`, not here.
struct BrowserSplitCardHoverTracker: NSViewRepresentable {
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSplitCardHoverTrackingView {
        BrowserSplitCardHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(
        _ nsView: BrowserSplitCardHoverTrackingView,
        context: Context
    ) {
        nsView.onHoverChange = onHoverChange
    }
}
