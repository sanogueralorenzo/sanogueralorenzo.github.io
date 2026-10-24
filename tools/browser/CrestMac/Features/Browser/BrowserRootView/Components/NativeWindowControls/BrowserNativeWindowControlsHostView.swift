import AppKit

// MARK: - Types

struct BrowserNativeWindowChromeSnapshot {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let toolbar: NSToolbar?
    let toolbarStyle: NSWindow.ToolbarStyle
    let contentFrameClipsToBounds: Bool
    let buttonVisibility: [(NSWindow.ButtonType, Bool)]
}

/// Styles the window that shows Crest's chrome, which acts as the window's
/// title bar: the title bar is transparent and shows no title, and the
/// window's own controls sit on the sidebar.
///
/// In fullscreen the title bar slides down over the page with the menu bar,
/// so there it is the system's standard one while it is revealed, from the
/// moment the window is fullscreen until it starts to leave. Hidden, it stays
/// transparent: WebKit pages keep the scroll edge effect they took from the
/// windowed title bar, which an opaque title bar draws as a band across the
/// top of every page. Neither writes the fullscreen bit of the style mask,
/// which AppKit owns during its transitions.
///
/// The window's toolbar only holds the title bar's metrics, so it shows only
/// outside fullscreen, whoever shows it. AppKit keeps a fullscreen window's
/// visible toolbar on screen once the title bar has revealed, and an empty one
/// would stay behind as a bar across the top of the window.
@MainActor
final class BrowserNativeWindowControlsHostView: NSView {
    // MARK: - Static Variables

    /// The standard window buttons the chrome hides, shows and moves.
    static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton,
    ]

    // MARK: - Variables

    private var originalChrome: BrowserNativeWindowChromeSnapshot?
    private var chromeToolbar: BrowserChromeToolbar?
    /// Follows the toolbar's visibility, which SwiftUI's bar appearance sets
    /// to shown whenever the window's content changes its bar preferences.
    private var toolbarVisibilityObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var nativeButtonOrigins: [NSWindow.ButtonType: CGFloat] = [:]
    var sidebarOnRight = false
    /// Whether the controls are crossing the window with the sidebar. AppKit
    /// lays its title bar out again on every window update, and putting them
    /// straight at their destination then would cut the move short.
    private var isMovingControls = false
    var sidebarWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        positionWindowControls()
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
        applySystemToolbarMetrics(to: window)
        let shouldShowWindowControls = window.styleMask.showsWindowControls(
            sidebarPresentationShowsControls: isVisible)
        for type in Self.buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let shouldHide = !shouldShowWindowControls
            guard button.isHidden != shouldHide else { continue }
            button.isHidden = shouldHide
        }
        positionWindowControls()
    }

    /// Shows the title bar as Crest's chrome, transparent and without a title
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

    /// Move the existing AppKit controls inside their titlebar, retaining their
    /// native actions, accessibility, sizes and order. Fullscreen owns placement.
    private func positionWindowControls(onRight: Bool? = nil, animated: Bool = false) {
        guard let window, animated || !isMovingControls, !window.styleMask.contains(.fullScreen) else { return }
        let offset =
            (onRight ?? sidebarOnRight)
            ? window.styleMask.windowControlsSidebarOffset(
                windowWidth: window.contentView?.bounds.width ?? bounds.width,
                sidebarWidth: sidebarWidth
            ) : 0
        for type in Self.buttonTypes {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            if nativeButtonOrigins[type] == nil {
                nativeButtonOrigins[type] = parent.convert(button.frame.origin, to: nil).x
            }
            guard let nativeX = nativeButtonOrigins[type] else { continue }
            let target = parent.convert(NSPoint(x: nativeX + offset, y: 0), from: nil).x
            if abs(button.frame.minX - target) > 0.5 {
                (animated ? button.animator() : button).setFrameOrigin(NSPoint(x: target, y: button.frame.minY))
            }
        }
    }

    /// Takes the controls to the sidebar's new side inside the animation the
    /// sidebar crosses the window with.
    func moveWindowControls(sidebarOnRight: Bool) {
        self.sidebarOnRight = sidebarOnRight
        isMovingControls = true
        positionWindowControls(animated: true)
    }

    func finishMovingWindowControls() {
        isMovingControls = false
        applyBrowserChrome()
    }

    func restoreWindowChrome() {
        stopObservingWindow()
        guard let window, let originalChrome else { return }
        isMovingControls = false
        positionWindowControls(onRight: false)
        nativeButtonOrigins.removeAll()
        window.styleMask = window.styleMask.restoringBrowserChrome(to: originalChrome.styleMask)
        window.titleVisibility = originalChrome.titleVisibility
        window.titlebarAppearsTransparent = originalChrome.titlebarAppearsTransparent
        window.titlebarSeparatorStyle = originalChrome.titlebarSeparatorStyle
        window.toolbar = originalChrome.toolbar
        window.toolbarStyle = originalChrome.toolbarStyle
        window.contentView?.superview?.clipsToBounds =
            originalChrome.contentFrameClipsToBounds
        for (type, wasHidden) in originalChrome.buttonVisibility {
            window.standardWindowButton(type)?.isHidden = wasHidden
        }
        toolbarVisibilityObservation = nil
        chromeToolbar = nil
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
            toolbarStyle: window.toolbarStyle,
            contentFrameClipsToBounds:
                window.contentView?.superview?.clipsToBounds ?? false,
            buttonVisibility: Self.buttonTypes.map { type in
                (type, window.standardWindowButton(type)?.isHidden ?? false)
            }
        )
    }

    private func applySystemToolbarMetrics(to window: NSWindow) {
        // This runs on every update of the sidebar's animation. On macOS 26,
        // writing the frame view's property again, even unchanged, has it
        // redraw, which flickers a fullscreen window until the menu bar's
        // reveal redraws it.
        if let frameView = window.contentView?.superview, !frameView.clipsToBounds {
            frameView.clipsToBounds = true
        }
        let toolbar: BrowserChromeToolbar
        if let chromeToolbar {
            toolbar = chromeToolbar
        } else {
            toolbar = BrowserChromeToolbar(
                identifier: BrowserChromeToolbar.chromeIdentifier
            )
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
            chromeToolbar = toolbar
            toolbarVisibilityObservation = toolbar.observe(\.isVisible) { [weak self] _, _ in
                // Settle after whoever changed it finishes its own update.
                DispatchQueue.main.async { [weak self] in
                    self?.applyBrowserChrome()
                }
            }
        }

        toolbar.chromeWindow = window
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        if window.toolbarStyle != .unified {
            window.toolbarStyle = .unified
        }
        let shouldShowToolbar = window.styleMask.showsBrowserToolbar
        if toolbar.isVisible != shouldShowToolbar {
            toolbar.isVisible = shouldShowToolbar
        }
    }

    // MARK: - Actions - Observing

    private func observeWindow() {
        stopObservingWindow()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didUpdateNotification,
            NSWindow.didResizeNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
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
        case NSWindow.didUpdateNotification:
            positionWindowControls()
            return
        case NSWindow.willEnterFullScreenNotification:
            positionWindowControls(onRight: false)
            return
        case NSWindow.didEnterFullScreenNotification:
            observeFullScreenTitleBar()
        case NSWindow.willExitFullScreenNotification:
            // The title bar returns to the window as it leaves fullscreen, so
            // it is Crest's again before it does.
            stopObservingFullScreenTitleBar()
            showsStandardTitleBar = false
            if let window { applyTitleBar(to: window) }
            return
        case NSWindow.didExitFullScreenNotification:
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
