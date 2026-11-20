import AppKit

/// Holds extend an existing hover. Sample the pointer because menu tracking can queue a stale exit.
@MainActor
final class BrowserSidebarHoverTrackingView: NSView {

    /// Keep the anchor visible while a dismissed menu or popover opens its successor.
    static let holdReleaseDelay: TimeInterval = 0.15

    var onHoverChange: @MainActor @Sendable (Bool) -> Void
    var waitsForPointer = false

    private let notificationCenter: NotificationCenter
    private let pointerLocation: @MainActor () -> NSPoint
    private let heldPopovers = NSHashTable<NSPopover>.weakObjects()
    private let heldWindows = NSHashTable<NSWindow>.weakObjects()
    private var trackingArea: NSTrackingArea?
    private var firstResponderObservation: NSKeyValueObservation?
    private var trackingMenus: Set<ObjectIdentifier> = []
    private var holdReleaseRevision = 0
    private var isReleasingHold = false
    private var lastReportedHover: Bool?

    private var isPointerInside: Bool {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(window.convertPoint(fromScreen: pointerLocation()), from: nil)
        return trackedRect.contains(location)
    }

    private var isHeldOpen: Bool {
        !trackingMenus.isEmpty
            || !heldPopovers.allObjects.isEmpty
            || !heldWindows.allObjects.isEmpty
            || isReleasingHold
            || isEditingInside
    }

    /// Resolve the text field through AppKit's shared field editor.
    private var isEditingInside: Bool {
        guard let window, let editor = window.firstResponder as? NSTextView else { return false }
        let field = editor.isFieldEditor ? (editor.delegate as? NSView) ?? editor : editor
        guard field.window === window, !field.isHiddenOrHasHiddenAncestor else { return false }
        // Full containment excludes fields partly covered by the floating sidebar.
        return trackedRect.contains(convert(field.convert(field.bounds, to: nil), from: nil))
    }

    private var trackedRect: NSRect {
        bounds.intersection(visibleRect)
    }

    init(
        notificationCenter: NotificationCenter = .default,
        pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation },
        onHoverChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.pointerLocation = pointerLocation
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        // Clip the tracker because inVisibleRect can otherwise extend beyond the sidebar.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notificationCenter.removeObserver(self)
        firstResponderObservation = nil
        trackingMenus.removeAll()
        heldPopovers.removeAllObjects()
        heldWindows.removeAllObjects()
        holdReleaseRevision += 1
        isReleasingHold = false
        lastReportedHover = nil
        guard let window else { return }
        let observations: [(Selector, Notification.Name, NSWindow?)] = [
            (#selector(menuTrackingBegan), NSMenu.didBeginTrackingNotification, nil),
            (#selector(menuTrackingEnded), NSMenu.didEndTrackingNotification, nil),
            (#selector(popoverWillShow), NSPopover.willShowNotification, nil),
            (#selector(popoverWillClose), NSPopover.willCloseNotification, nil),
            (#selector(anyWindowWillClose), NSWindow.willCloseNotification, nil),
            (#selector(windowResignedKey), NSWindow.didResignKeyNotification, window),
            (#selector(windowBecameKey), NSWindow.didBecomeKeyNotification, window),
        ]
        for (selector, name, object) in observations {
            notificationCenter.addObserver(self, selector: selector, name: name, object: object)
        }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            // Wait for the field editor to finish switching responders.
            DispatchQueue.main.async { [weak self] in
                self?.refreshPointerHover()
            }
        }
        schedulePointerRefresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        schedulePointerRefresh()
    }

    override func mouseEntered(with event: NSEvent) {
        refreshPointerHover()
    }

    override func mouseExited(with event: NSEvent) {
        refreshPointerHover()
    }

    func refreshPointerHover() {
        guard let window, !bounds.isEmpty else { return }
        releaseWindowsNoLongerShown()
        let isHovering = isPointerInside || (lastReportedHover == true && isHeldOpen)
        if waitsForPointer, lastReportedHover == nil, !isHovering,
            window.isKeyWindow, window.frame.contains(pointerLocation())
        {
            return
        }
        guard isHovering != lastReportedHover else { return }
        lastReportedHover = isHovering
        onHoverChange(isHovering)
    }

    func schedulePointerRefresh() {
        // Defer geometry reads and hover updates until SwiftUI layout settles.
        DispatchQueue.main.async { [weak self] in
            self?.refreshPointerHover()
        }
    }

    @objc private func menuTrackingBegan(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
            !trackingMenus.isEmpty || isPointerInside
        else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
        refreshPointerHover()
    }

    @objc private func menuTrackingEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
            trackingMenus.remove(ObjectIdentifier(menu)) != nil
        else { return }
        // Escape can dismiss the menu without generating another mouse event.
        beginHoldRelease()
    }

    /// Use the key window to identify the popover's origin before AppKit positions it.
    @objc private func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
            lastReportedHover == true,
            let window,
            let keyWindow = NSApp.keyWindow,
            keyWindow === window || isOpened(byThisWindow: keyWindow)
        else { return }
        heldPopovers.add(popover)
    }

    @objc private func popoverWillClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, heldPopovers.contains(popover) else { return }
        heldPopovers.remove(popover)
        beginHoldRelease()
    }

    @objc private func anyWindowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, heldWindows.contains(closing) else { return }
        heldWindows.remove(closing)
        beginHoldRelease()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        // AppKit assigns the next key window before delivering this notification.
        if lastReportedHover == true, let keyWindow = NSApp.keyWindow, isOpened(byThisWindow: keyWindow) {
            heldWindows.add(keyWindow)
        }
        refreshPointerHover()
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        // The popup can already be hidden when its parent becomes key, before the close notification.
        refreshPointerHover()
    }

    private func isOpened(byThisWindow candidate: NSWindow) -> Bool {
        guard let window, candidate !== window else { return false }
        return sequence(first: candidate, next: { $0.parent ?? $0.sheetParent })
            .dropFirst()
            .contains { $0 === window }
    }

    private func releaseWindowsNoLongerShown() {
        let hidden = heldWindows.allObjects.filter { !$0.isVisible }
        guard !hidden.isEmpty else { return }
        hidden.forEach(heldWindows.remove)
        beginHoldRelease()
    }

    private func beginHoldRelease() {
        holdReleaseRevision += 1
        let revision = holdReleaseRevision
        isReleasingHold = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdReleaseDelay) { [weak self] in
            guard let self, self.holdReleaseRevision == revision else { return }
            self.isReleasingHold = false
            self.refreshPointerHover()
        }
    }
}
