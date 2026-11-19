import AppKit

@MainActor
final class BrowserTitleBarPointerTracker: NSResponder {

    struct Region: Sendable {
        /// Claim the window below the title bar before the pointer can reach the drag strip.
        static let page = Region { location, page, window in
            guard location.y >= window.contentLayoutRect.maxY - BrowserTitleBarPointerTracker.approachMargin,
                !BrowserTitleBarPointerTracker.windowButtons.contains(where: {
                    BrowserTitleBarPointerTracker.isOnButton($0, location, in: window)
                }),
                let content = window.contentView,
                let target = content.hitTest(content.superview?.convert(location, from: nil) ?? location)
            else { return false }
            return target === page || target.isDescendant(of: page)
        }

        let contains: @MainActor @Sendable (NSPoint, NSView, NSWindow) -> Bool
    }

    private static let approachMargin: CGFloat = 32
    private static let windowButtons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    private weak var view: NSView?
    private let region: Region
    private weak var claimedWindow: NSWindow?
    private var pointerCheckIsPending = false

    init(view: NSView, region: Region) {
        self.view = view
        self.region = region
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    /// Track during drags so leaving the view with a button held ends the claim.
    func makeTrackingArea() -> NSTrackingArea {
        NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self
        )
    }

    override func mouseEntered(with event: NSEvent) {
        update(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        update(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        release()
    }

    /// Defer the check to avoid flushing the window during AppKit layout.
    func checkPointerSoon() {
        guard !pointerCheckIsPending else { return }
        pointerCheckIsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerCheckIsPending = false
            guard let window = self.view?.window,
                NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                    == window.windowNumber
            else {
                self.release()
                return
            }
            self.update(at: window.mouseLocationOutsideOfEventStream)
        }
    }

    func release() {
        guard let claimedWindow else { return }
        self.claimedWindow = nil
        BrowserWindowTitleBarGuard.guarding(claimedWindow).release(by: self)
    }

    private func update(at location: NSPoint) {
        guard let view, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
            Self.hasTitleBarStrip(window), region.contains(location, view, window)
        else {
            release()
            return
        }
        guard claimedWindow !== window else { return }
        release()
        claimedWindow = window
        BrowserWindowTitleBarGuard.guarding(window).claim(by: self)
    }

    private static func hasTitleBarStrip(_ window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen), let content = window.contentView else { return false }
        return window.contentLayoutRect.maxY < content.convert(content.bounds, to: nil).maxY
    }

    private static func isOnButton(_ type: NSWindow.ButtonType, _ location: NSPoint, in window: NSWindow) -> Bool {
        guard let button = window.standardWindowButton(type), !button.isHiddenOrHasHiddenAncestor else { return false }
        return button.convert(button.bounds, to: nil).contains(location)
    }
}
