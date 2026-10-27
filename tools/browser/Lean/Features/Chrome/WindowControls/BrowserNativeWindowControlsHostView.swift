import AppKit

// MARK: - Types

struct BrowserNativeWindowChromeSnapshot {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let toolbar: NSToolbar?
    let contentFrameClipsToBounds: Bool
    let buttonVisibility: [(NSWindow.ButtonType, Bool)]
}

/// Styles the window that shows Lean's chrome, which acts as the window's
/// title bar: the title bar is transparent and shows no title, and the
/// window's own controls align with Spaces independently of toolbar styling.
///
/// In fullscreen the title bar slides down over the page with the menu bar,
/// so there it is the system's standard one while it is revealed, from the
/// moment the window is fullscreen until it starts to leave. Hidden, it stays
/// transparent: WebKit pages keep the scroll edge effect they took from the
/// windowed title bar, which an opaque title bar draws as a band across the
/// top of every page. Neither writes the fullscreen bit of the style mask,
/// which AppKit owns during its transitions.
@MainActor
final class BrowserNativeWindowControlsHostView: NSView {
    // MARK: - Static Variables

    static let fullScreenEntryFailed = Notification.Name("LeanWindowFullScreenEntryFailed")

    /// The standard window buttons the chrome hides and shows.
    static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton,
    ]

    // MARK: - Variables

    private var originalChrome: BrowserNativeWindowChromeSnapshot?
    private var controlLayout: BrowserWindowControlLayout?
    private var enteringFullScreen = false
    private var windowObservers: [NSObjectProtocol] = []
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            applyBrowserChrome()
        }
    }
    /// Whether the window shows the system's standard title bar: while it is
    /// fullscreen and its title bar is revealed, and not once it starts to
    /// leave.
    private var showsStandardTitleBar = false
    /// Follows the window that holds the title bar in fullscreen, which AppKit
    /// shows from just before the title bar slides down with the menu bar
    /// until just after it slides away.
    private var fullScreenTitleBarObservation: NSKeyValueObservation?

    // MARK: - Actions - Window

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

    // MARK: - Actions - Chrome

    func applyBrowserChrome() {
        guard let window else { return }
        // The window stays movable, so its title bar and the system's window
        // commands move it as they move any window. A page under the title bar
        // keeps its presses through `BrowserWindowTitleBarGuard`.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        applyTitleBar(to: window)
        applyWindowShape(to: window)
        if !enteringFullScreen, !window.styleMask.contains(.fullScreen), controlLayout == nil {
            controlLayout = BrowserWindowControlLayout(window: window)
        }
        let shouldShowWindowControls = window.styleMask.showsWindowControls(
            sidebarPresentationShowsControls: isVisible)
        for type in Self.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let shouldHide = !shouldShowWindowControls
            guard button.isHidden != shouldHide else { continue }
            button.isHidden = shouldHide
        }
    }

    /// Shows the title bar as Lean's chrome, transparent and without a title
    /// or separator, or while it is revealed in fullscreen as the system's
    /// standard one.
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
        for (type, wasHidden) in originalChrome.buttonVisibility {
            window.standardWindowButton(type)?.isHidden = wasHidden
        }
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
            contentFrameClipsToBounds:
                window.contentView?.superview?.clipsToBounds ?? false,
            buttonVisibility: Self.buttonTypes.map { type in
                (type, window.standardWindowButton(type)?.isHidden ?? false)
            }
        )
    }

    private func applyWindowShape(to window: NSWindow) {
        // A toolbar, even an empty one, gives macOS windows larger corners.
        // The sidebar supplies all chrome, so use the smaller titlebar-only shape.
        if window.toolbar != nil {
            window.toolbar = nil
        }
        // Avoid resetting this during sidebar animation: AppKit redraws the frame.
        if let frameView = window.contentView?.superview, !frameView.clipsToBounds {
            frameView.clipsToBounds = true
        }
    }

    // MARK: - Actions - Observing

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
            // The title bar returns to the window as it leaves fullscreen, so
            // it is Lean's again before it does.
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

    /// In fullscreen the title bar moves to a window of its own, which AppKit
    /// makes visible just before the title bar slides down with the menu bar
    /// and invisible again just after it slides away. The title bar changes
    /// with that window in the same update, so the change never shows.
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
