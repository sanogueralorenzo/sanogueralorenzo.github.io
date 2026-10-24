import AppKit

/// Follows whether its window is in full screen, where the window has no
/// rounded corners for the page frame to follow.
@MainActor
final class BrowserWindowFullScreenHostView: NSView {
    // MARK: - Variables

    var fullScreenChanged: ((Bool) -> Void)?

    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var lastReportedFullScreen: Bool?

    // MARK: - Actions - Window

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if observedWindow !== window {
            stopObservingWindow()
            observedWindow = window
            observe(window)
        }
        report(window.styleMask.contains(.fullScreen))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Observing

    func stopObservingWindow() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedWindow = nil
        lastReportedFullScreen = nil
    }

    private func observe(_ window: NSWindow) {
        // The window squares its corners as it starts to enter full screen and
        // rounds them again as it starts to leave, before AppKit changes the
        // full-screen bit at either end.
        let transitions: [(Notification.Name, Bool)] = [
            (NSWindow.willEnterFullScreenNotification, true),
            (NSWindow.didEnterFullScreenNotification, true),
            (NSWindow.willExitFullScreenNotification, false),
            (NSWindow.didExitFullScreenNotification, false),
        ]
        let center = NotificationCenter.default
        observers = transitions.map { name, isFullScreen in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report(isFullScreen)
                }
            }
        }
    }

    private func report(_ isFullScreen: Bool) {
        guard lastReportedFullScreen != isFullScreen else { return }
        lastReportedFullScreen = isFullScreen
        Task { @MainActor [weak self] in
            self?.fullScreenChanged?(isFullScreen)
        }
    }
}
