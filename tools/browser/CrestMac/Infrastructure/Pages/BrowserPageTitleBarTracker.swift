import AppKit

/// Follows the pointer over one page and tells its window's title-bar guard
/// (`BrowserWindowTitleBarGuard`) while the pointer is on the page under the
/// title bar. The claim starts a little below the title bar, so a pointer on its
/// way up has already made the window unmovable before it can press there.
@MainActor
final class BrowserPageTitleBarTracker: NSResponder {
    // MARK: - Static Variables

    /// How far below the title bar the pointer already counts as under it.
    private static let approachMargin: CGFloat = 32
    /// The window's own buttons, which sit in its title bar above any page.
    private static let windowButtons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    // MARK: - Variables

    private weak var page: NSView?
    /// The window whose guard holds this page's claim.
    private weak var claimedWindow: NSWindow?
    private var pointerCheckIsPending = false

    // MARK: - Initializers

    init(page: NSView) {
        self.page = page
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Tracking

    /// The area to install on the page. It follows the page's visible rect, and
    /// keeps reporting while a button is held so a drag that leaves the page
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

    /// Checks the pointer where it is now, for a page that appeared, was shown
    /// or resized under a pointer that has not moved. The check waits for the
    /// next turn of the main queue: the page's geometry changes during AppKit's
    /// layout, and the guard must not flush the window from inside it. A
    /// pointer over another window above this one is not on the page.
    func checkPointerSoon() {
        guard !pointerCheckIsPending else { return }
        pointerCheckIsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerCheckIsPending = false
            guard let window = self.page?.window,
                NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                    == window.windowNumber
            else {
                self.release()
                return
            }
            self.update(at: window.mouseLocationOutsideOfEventStream)
        }
    }

    /// Ends this page's claim, for a pointer that left or a page that left its
    /// window or was hidden.
    func release() {
        guard let claimedWindow else { return }
        self.claimedWindow = nil
        BrowserWindowTitleBarGuard.guarding(claimedWindow).release(by: self)
    }

    private func update(at location: NSPoint) {
        guard let page, let window = page.window, Self.isUnderTitleBar(location, of: page, in: window) else {
            release()
            return
        }
        guard claimedWindow !== window else { return }
        release()
        claimedWindow = window
        BrowserWindowTitleBarGuard.guarding(window).claim(by: self)
    }

    /// Whether `location`, in `window`'s coordinates, is on `page` in the strip
    /// under the window's title bar or just below it. A window in fullscreen, or
    /// one whose content stops at its title bar, has no such strip. The page
    /// must be what a press there would reach, so the window's own buttons and
    /// chrome drawn over the page, such as a floating sidebar, stay the title
    /// bar's.
    private static func isUnderTitleBar(_ location: NSPoint, of page: NSView, in window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen), !page.isHiddenOrHasHiddenAncestor,
            let content = window.contentView
        else { return false }
        let titleBarBottom = window.contentLayoutRect.maxY
        guard titleBarBottom < content.convert(content.bounds, to: nil).maxY,
            location.y >= titleBarBottom - approachMargin,
            !windowButtons.contains(where: { isOnButton($0, location, in: window) }),
            let target = content.hitTest(content.superview?.convert(location, from: nil) ?? location)
        else { return false }
        return target === page || target.isDescendant(of: page)
    }

    private static func isOnButton(_ type: NSWindow.ButtonType, _ location: NSPoint, in window: NSWindow) -> Bool {
        guard let button = window.standardWindowButton(type), !button.isHiddenOrHasHiddenAncestor else { return false }
        return button.convert(button.bounds, to: nil).contains(location)
    }
}
