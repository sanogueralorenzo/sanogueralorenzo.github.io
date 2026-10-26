import AppKit

/// Answers for a browser window's content when a mouse's Back or Forward
/// button is pressed, or a swipe no page took reaches the window. It covers
/// the sidebar and asks for the window's pages at event time, so it tells a
/// press over a page from one over the sidebar. It answers while it is in a
/// window; the shell's `BrowserMacMouseButtons` pairs each press it took with
/// its release, so SwiftUI rebuilding or moving this view in between changes
/// nothing.
@MainActor
final class BrowserSidebarPointerNavigationView: NSView, BrowserMacWindowPointerNavigation {
    // MARK: - Variables

    var perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
    /// The window's live pages, asked for at event time so a page created or
    /// released since the last SwiftUI update is never consulted.
    var navigationTargets: @MainActor @Sendable () -> [any BrowserSidebarMouseNavigationTarget]
    /// The page the window shows, which a swipe over no page moves.
    var activeTarget: @MainActor @Sendable () -> (any BrowserSidebarMouseNavigationTarget)?

    // MARK: - Initializers

    init(
        perform: @escaping @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void,
        navigationTargets:
            @escaping @MainActor @Sendable ()
            -> [any BrowserSidebarMouseNavigationTarget],
        activeTarget: @escaping @MainActor @Sendable () -> (any BrowserSidebarMouseNavigationTarget)?
    ) {
        self.perform = perform
        self.navigationTargets = navigationTargets
        self.activeTarget = activeTarget
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let current = window as? BrowserMacWindow, current.pointerNavigation === self else { return }
        current.pointerNavigation = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        answerForWindow()
    }

    /// Makes this view the one its window asks, as the sidebar SwiftUI shows
    /// now.
    func answerForWindow() {
        (window as? BrowserMacWindow)?.pointerNavigation = self
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Actions - Pointer navigation

    func takePress(_ action: BrowserSidebarMouseButtonAction, at event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let page = pageUnderPointer(for: event)
        guard
            let disposition = pointerScope(for: event, page: page).disposition(
                for: action,
                canNavigatePage: canNavigate(action, in: page)
            )
        else { return false }

        disposition.take(on: self, page: page)
        return true
    }

    /// Logitech Options+ sends a mouse's Back and Forward buttons as swipes,
    /// so a swipe is answered as a press where the pointer is.
    func navigate(_ action: BrowserSidebarMouseButtonAction, swipedAt event: NSEvent) -> Bool {
        if takePress(action, at: event) { return true }
        guard event.window === window, let page = activeTarget(), canNavigate(action, in: page)
        else { return false }
        navigate(action, in: page)
        return true
    }

    private func pointerScope(
        for event: NSEvent,
        page: (any BrowserSidebarMouseNavigationTarget)?
    ) -> BrowserSidebarMousePointerScope {
        if page != nil { return .webpage }
        guard !isHidden else { return .unowned }
        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location) ? .sidebar : .unowned
    }

    private func canNavigate(
        _ action: BrowserSidebarMouseButtonAction,
        in page: (any BrowserSidebarMouseNavigationTarget)?
    ) -> Bool {
        guard let page else { return false }
        return action.canNavigate(page)
    }

    /// Moves `page`, if there is one, the way `action` asks.
    func navigate(
        _ action: BrowserSidebarMouseButtonAction,
        in page: (any BrowserSidebarMouseNavigationTarget)?
    ) {
        guard let page else { return }
        action.navigate(page)
    }

    /// Matches the hit view against the pages this window owns rather than a
    /// view class, so every engine's page content answers the same way.
    private func pageUnderPointer(
        for event: NSEvent
    ) -> (any BrowserSidebarMouseNavigationTarget)? {
        guard let contentView = window?.contentView else { return nil }
        let targets = navigationTargets()
        guard !targets.isEmpty else { return nil }
        let location = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(location)
        while let view = candidate {
            if let match = targets.first(where: { $0.nativeView === view }) {
                return match
            }
            candidate = view.superview
        }
        return nil
    }
}
