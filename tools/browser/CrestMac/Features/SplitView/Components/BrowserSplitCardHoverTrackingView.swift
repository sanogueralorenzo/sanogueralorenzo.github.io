import AppKit

/// A transparent view that reports the pointer entering and leaving its bounds.
///
/// SwiftUI's `.onHover` is not usable here: a card's content is a `WKWebView`, and
/// hover callbacks over live web content arrive late, arrive once, or do not
/// arrive at all depending on what the page does with the pointer. An
/// `NSTrackingArea` is answered by AppKit's own tracking machinery instead of by
/// the view under the cursor, so it reports the truth regardless of the page.
///
/// The view is inert in every other respect. `hitTest` returns `nil`, so it can
/// sit above live web content — where tracking is most reliable — without taking
/// a single click, scroll, or drag away from the page beneath it.
///
/// `.inVisibleRect` means the tracked region follows the view's visible bounds,
/// so a card that resizes, scrolls, or is clipped by a narrowing window needs no
/// rebuild of its own. `.activeInKeyWindow` keeps a background window from moving
/// focus in the window someone is actually working in.
@MainActor
final class BrowserSplitCardHoverTrackingView: NSView {
    var onHoverChange: @MainActor @Sendable (Bool) -> Void

    private var trackingArea: NSTrackingArea?

    init(onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void) {
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            // `.inVisibleRect` supplies the rect, so this one is ignored.
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }
}
