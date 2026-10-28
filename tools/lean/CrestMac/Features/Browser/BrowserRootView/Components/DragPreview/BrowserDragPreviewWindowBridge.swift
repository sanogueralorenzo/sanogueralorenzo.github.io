import SwiftUI

/// Puts whatever is travelling on the pointer in a window of its own, for as
/// long as it is travelling.
///
/// Zero-sized and inert: it exists only to reach the `NSWindow` this browser
/// window is drawn in, so the preview can be ordered above it. Everything it
/// shows is decided by the state that owns the gesture — the sidebar's reorder
/// state, the window's card lift — read through ordinary observation, so the
/// window follows the pointer for the same reason the rows and cards do.
struct BrowserDragPreviewWindowBridge: NSViewRepresentable {
    let content: BrowserDragPreviewWindowContent?
    var onSidebarLandingComplete: (UUID) -> Void = { _ in }
    var onSidebarLandingArrived: (UUID) -> Void = { _ in }

    func makeNSView(context: Context) -> BrowserDragPreviewWindowHostView {
        let view = BrowserDragPreviewWindowHostView()
        view.onSidebarLandingComplete = onSidebarLandingComplete
        view.onSidebarLandingArrived = onSidebarLandingArrived
        view.content = content
        return view
    }

    func updateNSView(
        _ nsView: BrowserDragPreviewWindowHostView,
        context: Context
    ) {
        nsView.onSidebarLandingComplete = onSidebarLandingComplete
        nsView.onSidebarLandingArrived = onSidebarLandingArrived
        nsView.content = content
    }

    static func dismantleNSView(
        _ nsView: BrowserDragPreviewWindowHostView,
        coordinator: Void
    ) {
        nsView.teardown()
    }
}
