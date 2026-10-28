import SwiftUI

/// Installs the split surface's single pointer monitor: the one that turns a
/// click into a focused card and a ⇧⌘-held press into a carried one.
///
/// Attached as the background of the same view that declares
/// `BrowserSplitCardFrameRegistry.coordinateSpace`, which is what makes the
/// monitor's bounds and the registered card frames share an origin. Moving this
/// to a different view than the one carrying that coordinate space would offset
/// every hit test by the difference.
struct BrowserSplitCardPointerMonitor: NSViewRepresentable {
    let cardFrames: BrowserSplitCardFrameRegistry
    /// Called with the card a mouse-down landed in. The event is delivered to the
    /// page either way, so this is a notification and never a veto.
    let handleMouseDown: @MainActor @Sendable (UUID) -> Void
    /// What the monitor may do to a carry. Unlike the focus notification, a
    /// pickup *is* a veto: the events that carry a card belong to the carry.
    let lift: BrowserSplitCardLiftGesture

    func makeNSView(context: Context) -> BrowserSplitCardPointerObserverView {
        BrowserSplitCardPointerObserverView(
            cardFrames: cardFrames,
            handleMouseDown: handleMouseDown,
            lift: lift
        )
    }

    func updateNSView(
        _ nsView: BrowserSplitCardPointerObserverView,
        context: Context
    ) {
        nsView.cardFrames = cardFrames
        nsView.handleMouseDown = handleMouseDown
        nsView.lift = lift
    }

    static func dismantleNSView(
        _ nsView: BrowserSplitCardPointerObserverView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}
