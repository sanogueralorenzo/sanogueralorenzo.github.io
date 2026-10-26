import AppKit

@MainActor
final class BrowserWindowFocusHostView: NSView {
    var focusChanged: ((Bool) -> Void)?

    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var lastReportedFocus: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if observedWindow !== window {
            stopObservingWindow()
            observedWindow = window
            observe(window)
        }
        reportFocus(window.isKeyWindow)
    }

    func stopObservingWindow() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedWindow = nil
        lastReportedFocus = nil
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportFocus(true) }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportFocus(false) }
            },
        ]
    }

    private func reportFocus(_ isFocused: Bool) {
        guard lastReportedFocus != isFocused else { return }
        lastReportedFocus = isFocused
        Task { @MainActor [weak self] in
            self?.focusChanged?(isFocused)
        }
    }
}
