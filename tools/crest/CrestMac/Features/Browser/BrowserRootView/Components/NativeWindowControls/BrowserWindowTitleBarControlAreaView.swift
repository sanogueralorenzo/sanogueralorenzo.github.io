import AppKit

/// The area of a control that sits under the window's title bar, such as the
/// Quick Window's address field, which keeps the control's presses while the
/// pointer is on it.
///
/// The window server drags a movable window from the whole strip under its
/// title bar before the app sees a press, and SwiftUI claims none of that strip
/// for the controls it hosts, so a drag across the field's text moved the
/// window instead of selecting it. While the pointer is on the area, its
/// tracker (`BrowserTitleBarPointerTracker`) holds the window still, as it does
/// for a page there. The area takes no presses of its own, and the chrome
/// around it still moves the window.
@MainActor
final class BrowserWindowTitleBarControlAreaView: NSView {
    // MARK: - Variables

    private lazy var tracker = BrowserTitleBarPointerTracker(view: self, region: .control)
    /// The window's full-screen notifications this area follows.
    private var fullScreenObservers: [NSObjectProtocol] = []

    // MARK: - Initializers

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(tracker.makeTrackingArea())
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Tracking

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            tracker.release()
            stopFollowingFullScreen()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        followFullScreen()
        tracker.checkPointerSoon()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tracker.checkPointerSoon()
    }

    override func viewDidHide() {
        super.viewDidHide()
        tracker.release()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        tracker.checkPointerSoon()
    }

    // MARK: - Actions - Full Screen

    /// Checks the pointer again as the window enters or leaves full screen. A
    /// window already as wide as the screen changes mode without resizing the
    /// area, so neither a frame change nor the pointer would end a claim that
    /// full screen no longer allows.
    private func followFullScreen() {
        stopFollowingFullScreen()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification,
        ]
        fullScreenObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tracker.checkPointerSoon() }
            }
        }
    }

    private func stopFollowingFullScreen() {
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers = []
    }
}
