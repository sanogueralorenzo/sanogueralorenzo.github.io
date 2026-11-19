import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    var isRevealedByPointer = false
    var exitMargin: CGFloat = 0
    var exitEdge: HorizontalEdge = .trailing
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.isRevealedByPointer = isRevealedByPointer
        view.setExitMargin(exitMargin, on: exitRectEdge(in: context.environment.layoutDirection))
        view.schedulePointerRefresh()
    }

    /// Resolve logical edges because AppKit coordinates are always left to right.
    private func exitRectEdge(in layoutDirection: LayoutDirection) -> CGRectEdge {
        (exitEdge == .trailing) == (layoutDirection == .leftToRight) ? .maxXEdge : .minXEdge
    }
}
