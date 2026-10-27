import AppKit
import SwiftUI

/// Window-level tracking stays reliable while WebKit or another native child owns input.
struct BrowserSidebarPointerTracker: NSViewRepresentable {
    let store: BrowserStore
    func makeNSView(context: Context) -> SidebarPointerView { SidebarPointerView(store: store) }
    func updateNSView(_ view: SidebarPointerView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            view?.updateTrackingAreas()
            view?.refreshExistingHover()
        }
    }
}

@MainActor final class SidebarPointerView: NSView {
    weak var store: BrowserStore?
    private let pointer: () -> NSPoint
    private var restingPointer: NSPoint?
    private var area: NSTrackingArea?

    init(store: BrowserStore, pointer: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.store = store
        self.pointer = pointer
        super.init(frame: .zero)
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        restingPointer = window == nil ? nil : pointer()
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let width =
            store.map {
                $0.showsSidebar
                    ? $0.sidebarWidth + SidebarGeometry.inset + SidebarGeometry.hoverMargin
                    : SidebarGeometry.hoverMargin
            } ?? 0
        let rect = bounds.intersection(NSRect(x: 0, y: 0, width: width, height: bounds.height))
        let next = NSTrackingArea(
            rect: rect, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self)
        addTrackingArea(next)
        area = next
    }
    override func mouseEntered(with event: NSEvent) { pointerMoved() }
    override func mouseMoved(with event: NSEvent) { pointerMoved() }
    override func mouseExited(with event: NSEvent) { refreshExistingHover() }

    @objc private func windowResignedKey() {
        restingPointer = pointer()
        store?.sidebarRevealed = false
    }
    @objc private func windowBecameKey() {
        restingPointer = pointer()
        refreshExistingHover()
    }
    func pointerMoved() {
        let location = pointer()
        if let restingPointer, location == restingPointer { return }
        restingPointer = nil
        refresh(allowReveal: true)
    }
    func refreshExistingHover() { refresh(allowReveal: false) }

    private func refresh(allowReveal: Bool) {
        guard let store, let window else { return }
        let location = pointer()
        let point = window.convertPoint(fromScreen: location)
        let inside =
            window.isKeyWindow && window.frame.contains(location)
            && SidebarGeometry.containsPointer(
                x: point.x, sidebarVisible: store.showsSidebar, width: store.sidebarWidth)
        let revealed = inside && (allowReveal || store.sidebarRevealed)
        if store.sidebarRevealed != revealed { store.sidebarRevealed = revealed }
    }
}
