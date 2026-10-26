import AppKit

/// Watches the window's pointer for the two things Split View does with one:
/// focus follows a click, and a ⇧⌘-held press picks a card up and carries it.
///
/// A `TapGesture` cannot do either. Web content consumes its own clicks, so a
/// gesture attached above a `WKWebView` never sees the click that focuses a card
/// — which is nearly every click somebody makes — and a `DragGesture` over the
/// page never begins at all. A local `NSEvent` monitor sees each event before
/// the window dispatches it, which is the one place both are still available.
///
/// One monitor per window, not one per card. Four cards would install four
/// monitors that all see the same event and all have to work out whether it was
/// theirs; the frame registry answers that question once.
///
/// The two jobs differ in exactly one way, and it is the important one. Focus is
/// a notification: the event is returned unmodified and the page still receives
/// it, so focus follows the click instead of costing one. A carry is a veto: the
/// press that picked the card up, every drag that moves it, the release that
/// puts it down, and the Escape that calls it off all belong to the carry, and
/// none of them reaches the page. Anything else would leave a text selection
/// smeared across the page somebody was only rearranging.
///
/// The view holds no state of its own — not even "am I carrying". That answer
/// lives in the lift state, which is the only thing that can know it: a carry
/// ends by release, by Escape, by right-click, by the window losing key, by the
/// card leaving the row, and by the row leaving the screen, and only some of
/// those pass through here. A remembered copy would survive the ones that do
/// not, and a monitor that wrongly believes it is carrying swallows every press
/// that follows — which is a window that can never pick anything up again.
///
/// The view is flipped and reports the event location in its own bounds, which is
/// what makes the geometry exact: SwiftUI registers card frames in a coordinate
/// space anchored on the very view this one spans, so `convert(_:from: nil)` on a
/// flipped view lands in the same space with no window-chrome arithmetic anywhere.
/// `hitTest` returns `nil` so the view itself is never a click target.
@MainActor
final class BrowserSplitCardPointerObserverView: NSView {
    var cardFrames: BrowserSplitCardFrameRegistry
    var handleMouseDown: @MainActor @Sendable (UUID) -> Void
    var lift: BrowserSplitCardLiftGesture

    private static let escapeKeyCode: UInt16 = 53

    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(
        cardFrames: BrowserSplitCardFrameRegistry,
        handleMouseDown: @escaping @MainActor @Sendable (UUID) -> Void,
        lift: BrowserSplitCardLiftGesture
    ) {
        self.cardFrames = cardFrames
        self.handleMouseDown = handleMouseDown
        self.lift = lift
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A row that has left the screen cannot be carrying anything, and the
        // release that would have ended the carry is going somewhere else now.
        if window == nil {
            endCarry(cancelled: true)
        }
        updateEventMonitor()
        observeInterruptions()
    }

    func stopMonitoring() {
        endCarry(cancelled: true)
        stopObserving()
        removeEventMonitor()
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func updateEventMonitor() {
        removeEventMonitor()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
                .keyDown,
            ]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !lift.isCarrying() else { return handleCarried(event) }
        guard event.window === window else { return event }

        switch event.type {
        case .leftMouseDown:
            let location = convert(event.locationInWindow, from: nil)
            if lift.begin(location, BrowserKeyboardModifierFlags(event.modifierFlags)) {
                return nil
            }
            return notifyMouseDown(at: location, event)
        case .rightMouseDown, .otherMouseDown:
            return notifyMouseDown(
                at: convert(event.locationInWindow, from: nil),
                event
            )
        default:
            return event
        }
    }

    /// Always returns `event`. A monitor that swallowed the click would trade a
    /// focus change for the interaction somebody actually made.
    private func notifyMouseDown(at location: CGPoint, _ event: NSEvent) -> NSEvent {
        guard let tabID = cardFrames.tabID(containing: location) else {
            return event
        }
        handleMouseDown(tabID)
        return event
    }

    /// Every event during a carry belongs to the carry, so all of them are kept.
    ///
    /// A key-down is the exception that proves it: Escape ends the carry and is
    /// swallowed, and everything else passes so that a menu key equivalent still
    /// reaches the menu rather than disappearing into a drag.
    private func handleCarried(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDragged:
            if let location = pointerLocation() {
                lift.update(location)
            }
            return nil
        case .leftMouseUp:
            endCarry(cancelled: false)
            return nil
        case .rightMouseDown, .otherMouseDown, .leftMouseDown:
            endCarry(cancelled: true)
            return nil
        case .keyDown where event.keyCode == Self.escapeKeyCode:
            endCarry(cancelled: true)
            return nil
        default:
            return event
        }
    }

    private func endCarry(cancelled: Bool) {
        guard lift.isCarrying() else { return }
        if cancelled {
            lift.cancel()
        } else {
            lift.drop()
        }
    }

    /// The pointer in this view's own space, read from the screen rather than
    /// from the event.
    ///
    /// A carried card follows the pointer wherever it goes, including off the
    /// window entirely, and an event that lands outside the window reports a
    /// location in a space this view cannot convert from. The screen position is
    /// the one reading that is true everywhere.
    private func pointerLocation() -> CGPoint? {
        guard let window else { return nil }
        return convert(
            window.convertPoint(fromScreen: NSEvent.mouseLocation),
            from: nil
        )
    }

    /// Everything that takes the pointer away mid-carry without ever delivering
    /// the release that would have ended it.
    ///
    /// A window that stops being key has lost the pointer to something else; a
    /// window that closes has lost it altogether; an application that stops being
    /// active has handed the whole event stream over. In each case the card goes
    /// back where it came from rather than waiting for a release that is never
    /// coming.
    private func observeInterruptions() {
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        let cancel: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.endCarry(cancelled: true) }
        }
        observers = [
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main,
                using: cancel
            ),
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main,
                using: cancel
            ),
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main,
                using: cancel
            ),
        ]
    }

    private func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
