import AppKit

/// Follows the pointer over one view under the window's title bar, a page or
/// a control such as a Quick Window's address field, and tells its window's
/// title-bar guard (`BrowserWindowTitleBarGuard`) while the pointer is on that
/// view there. The view's region says where it counts as under the title bar.
@MainActor
final class BrowserTitleBarPointerTracker: NSResponder {
    // MARK: - Types

    /// Where a tracked view holds its window still, given a pointer location in
    /// the window's coordinates.
    struct Region: Sendable {
        /// A page holds the window from a little below the title bar, so a
        /// pointer on its way up has already made the window unmovable before
        /// it can press there. The page must be what a press there would reach,
        /// so the window's own buttons and chrome drawn over the page, such as a
        /// floating sidebar, stay the title bar's.
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

        /// A control holds the window anywhere on it once any of it reaches
        /// into the strip, so a pointer that crosses into the strip on its way
        /// to a press has already made the window unmovable. The control takes
        /// no presses of its own, so its bounds stand in for a hit test.
        static let control = Region { location, control, window in
            control.convert(control.bounds, to: nil).maxY > window.contentLayoutRect.maxY
                && control.bounds.contains(control.convert(location, from: nil))
        }

        let contains: @MainActor @Sendable (NSPoint, NSView, NSWindow) -> Bool
    }

    // MARK: - Static Variables

    /// How far below the title bar a page already counts as under it.
    private static let approachMargin: CGFloat = 32
    /// The window's own buttons, which sit in its title bar above any page.
    private static let windowButtons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    // MARK: - Variables

    private weak var view: NSView?
    private let region: Region
    /// The window whose guard holds this view's claim.
    private weak var claimedWindow: NSWindow?
    private var pointerCheckIsPending = false

    // MARK: - Initializers

    init(view: NSView, region: Region) {
        self.view = view
        self.region = region
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Tracking

    /// The area to install on the view. It follows the view's visible rect, and
    /// keeps reporting while a button is held so a drag that leaves the view
    /// still ends the claim.
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

    /// Checks the pointer where it is now, for a view that appeared, was shown
    /// or resized under a pointer that has not moved. The check waits for the
    /// next turn of the main queue: the view's geometry changes during AppKit's
    /// layout, and the guard must not flush the window from inside it. A
    /// pointer over another window above this one is not on the view.
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

    /// Ends this view's claim, for a pointer that left or a view that left its
    /// window or was hidden.
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

    /// Whether `window` has a strip under its title bar to hold. A window in
    /// fullscreen, or one whose content stops at its title bar, has none.
    private static func hasTitleBarStrip(_ window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen), let content = window.contentView else { return false }
        return window.contentLayoutRect.maxY < content.convert(content.bounds, to: nil).maxY
    }

    private static func isOnButton(_ type: NSWindow.ButtonType, _ location: NSPoint, in window: NSWindow) -> Bool {
        guard let button = window.standardWindowButton(type), !button.isHiddenOrHasHiddenAncestor else { return false }
        return button.convert(button.bounds, to: nil).contains(location)
    }
}
