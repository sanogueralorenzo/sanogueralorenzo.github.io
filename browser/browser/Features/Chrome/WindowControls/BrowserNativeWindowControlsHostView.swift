import AppKit

struct BrowserNativeWindowChromeSnapshot {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let toolbar: NSToolbar?
    let contentFrameClipsToBounds: Bool
}

/// Keep the hidden fullscreen title bar transparent to avoid a band on WebKit pages.
@MainActor
final class BrowserNativeWindowControlsHostView: NSView {

    static let fullScreenEntryFailed = Notification.Name("BrowserWindowFullScreenEntryFailed")

    static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton,
    ]

    private var originalChrome: BrowserNativeWindowChromeSnapshot?
    private var controlLayout: BrowserWindowControlLayout?
    private var enteringFullScreen = false
    private var windowObservers: [NSObjectProtocol] = []
    var sidebarOffset: CGFloat = 0 {
        didSet { controlLayout?.update(sidebarOffset: sidebarOffset) }
    }
    private var showsStandardTitleBar = false
    private var fullScreenTitleBarObservation: NSKeyValueObservation?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            restoreWindowChrome()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        showsStandardTitleBar = false
        captureOriginalChrome()
        observeWindow()
        if window?.styleMask.contains(.fullScreen) == true {
            observeFullScreenTitleBar()
        }
        applyBrowserChrome()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func applyBrowserChrome() {
        guard let window else { return }
        // Keep native window movement available while the title-bar guard protects page clicks.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        applyTitleBar(to: window)
        applyWindowShape(to: window)
        if !enteringFullScreen, !window.styleMask.contains(.fullScreen), controlLayout == nil {
            controlLayout = BrowserWindowControlLayout(window: window)
            controlLayout?.update(sidebarOffset: sidebarOffset)
        }
    }

    private func applyTitleBar(to window: NSWindow) {
        let standard = showsStandardTitleBar
        let titleVisibility: NSWindow.TitleVisibility = standard ? .visible : .hidden
        if window.titleVisibility != titleVisibility {
            window.titleVisibility = titleVisibility
        }
        if window.titlebarAppearsTransparent == standard {
            window.titlebarAppearsTransparent = !standard
        }
        let separatorStyle: NSTitlebarSeparatorStyle = standard ? .automatic : .none
        if window.titlebarSeparatorStyle != separatorStyle {
            window.titlebarSeparatorStyle = separatorStyle
        }
    }

    func restoreWindowChrome() {
        stopObservingWindow()
        controlLayout?.restore()
        controlLayout = nil
        enteringFullScreen = false
        guard let window, let originalChrome else { return }
        window.styleMask = window.styleMask.restoringBrowserChrome(to: originalChrome.styleMask)
        window.titleVisibility = originalChrome.titleVisibility
        window.titlebarAppearsTransparent = originalChrome.titlebarAppearsTransparent
        window.titlebarSeparatorStyle = originalChrome.titlebarSeparatorStyle
        window.toolbar = originalChrome.toolbar
        window.contentView?.superview?.clipsToBounds =
            originalChrome.contentFrameClipsToBounds
        self.originalChrome = nil
    }

    private func captureOriginalChrome() {
        guard let window, originalChrome == nil else { return }
        originalChrome = BrowserNativeWindowChromeSnapshot(
            styleMask: window.styleMask,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            titleVisibility: window.titleVisibility,
            titlebarSeparatorStyle: window.titlebarSeparatorStyle,
            toolbar: window.toolbar,
            contentFrameClipsToBounds: window.contentView?.superview?.clipsToBounds ?? false
        )
    }

    private func applyWindowShape(to window: NSWindow) {
        // Even an empty toolbar makes macOS use larger window corners.
        if window.toolbar != nil {
            window.toolbar = nil
        }
        // Avoid resetting this during sidebar animation: AppKit redraws the frame.
        if let frameView = window.contentView?.superview, !frameView.clipsToBounds {
            frameView.clipsToBounds = true
        }
    }

    private func observeWindow() {
        stopObservingWindow()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResizeNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            Self.fullScreenEntryFailed,
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.windowChanged(name)
                }
            }
        }
    }

    private func windowChanged(_ name: Notification.Name) {
        switch name {
        case NSWindow.willEnterFullScreenNotification:
            enteringFullScreen = true
            controlLayout?.restore()
            controlLayout = nil
        case NSWindow.didEnterFullScreenNotification:
            enteringFullScreen = false
            observeFullScreenTitleBar()
        case NSWindow.willExitFullScreenNotification:
            // Restore Browser chrome before AppKit moves the title bar back from fullscreen.
            stopObservingFullScreenTitleBar()
            showsStandardTitleBar = false
            if let window { applyTitleBar(to: window) }
            return
        case NSWindow.didExitFullScreenNotification, Self.fullScreenEntryFailed:
            enteringFullScreen = false
            showsStandardTitleBar = false
        default:
            break
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyBrowserChrome()
        }
    }

    /// AppKit makes the fullscreen title-bar window visible before the slide and hides it after.
    private func observeFullScreenTitleBar() {
        stopObservingFullScreenTitleBar()
        guard let window,
            let titleBarWindow = window.standardWindowButton(.closeButton)?.window,
            titleBarWindow !== window
        else { return }
        fullScreenTitleBarObservation = titleBarWindow.observe(
            \.alphaValue,
            options: [.initial]
        ) { [weak self] titleBarWindow, _ in
            MainActor.assumeIsolated {
                self?.fullScreenTitleBarChanged(isRevealed: titleBarWindow.alphaValue > 0)
            }
        }
    }

    private func fullScreenTitleBarChanged(isRevealed: Bool) {
        guard showsStandardTitleBar != isRevealed, let window else { return }
        showsStandardTitleBar = isRevealed
        applyTitleBar(to: window)
    }

    private func stopObservingFullScreenTitleBar() {
        fullScreenTitleBarObservation?.invalidate()
        fullScreenTitleBarObservation = nil
    }

    private func stopObservingWindow() {
        stopObservingFullScreenTitleBar()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
