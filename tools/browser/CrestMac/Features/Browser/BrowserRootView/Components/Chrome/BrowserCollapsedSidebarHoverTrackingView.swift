import AppKit

/// A transparent leading-edge view whose hover events come from AppKit.
///
/// SwiftUI's `.onHover` can miss the transition when the view behind the edge
/// is a live `WKWebView`. `NSTrackingArea` observes the window-level pointer
/// crossing instead, while `hitTest` keeps clicks, scrolling, and page drags
/// owned by the shared reveal button and the web content beneath it.
///
/// The strip reveals only for a pointer that moves onto it. One already resting
/// where the strip appears, as the sidebar it just hid slides away, has not
/// reached for the edge again: Universal Control leaves the pointer parked
/// there after crossing to another Mac.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private let pointerLocation: @MainActor () -> NSPoint
    private var trackingArea: NSTrackingArea?
    /// Where the pointer rested when the strip appeared, until it moves.
    private var restingPointer: NSPoint?

    init(
        pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation },
        onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.pointerLocation = pointerLocation
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restingPointer = window == nil ? nil : pointerLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportHoverIfPointerMoved()
    }

    override func mouseMoved(with event: NSEvent) {
        reportHoverIfPointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        restingPointer = nil
        reportHover(false)
    }

    func reportHover(_ isHovering: Bool) {
        onHoverChange(isHovering)
    }

    private func reportHoverIfPointerMoved() {
        if let restingPointer {
            guard pointerLocation() != restingPointer else { return }
            self.restingPointer = nil
        }
        reportHover(true)
    }
}
