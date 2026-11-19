import AppKit

/// Use AppKit tracking because SwiftUI hover can miss crossings over WKWebView.
/// Require movement onto the strip because Universal Control can leave the pointer parked there.
@MainActor
final class BrowserCollapsedSidebarHoverTrackingView: NSView {
    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private let pointerLocation: @MainActor () -> NSPoint
    private var trackingArea: NSTrackingArea?
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
