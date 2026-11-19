import AppKit
import QuartzCore

/// The window server can start a title-bar drag over a SwiftUI-hosted page before Browser sees the press.
/// Disable dragging over page controls and yield to Globe-Control tiling.
@MainActor
final class BrowserWindowTitleBarGuard {

    private static let guards = NSMapTable<NSWindow, BrowserWindowTitleBarGuard>.weakToStrongObjects()
    private static let tilingModifiers: NSEvent.ModifierFlags = [.function, .control]
    private static var tilingModifiersAreHeld = false
    private static var modifierMonitor: Any?

    private weak var window: NSWindow?
    private var claims: Set<ObjectIdentifier> = []
    private var restoredMovability = true
    private var holdsWindow = false

    private init(window: NSWindow) {
        self.window = window
    }

    static func guarding(_ window: NSWindow) -> BrowserWindowTitleBarGuard {
        if let existing = guards.object(forKey: window) { return existing }
        let created = BrowserWindowTitleBarGuard(window: window)
        guards.setObject(created, forKey: window)
        watchTilingModifiers()
        return created
    }

    func claim(by page: AnyObject) {
        guard claims.insert(ObjectIdentifier(page)).inserted else { return }
        apply()
    }

    func release(by page: AnyObject) {
        guard claims.remove(ObjectIdentifier(page)) != nil else { return }
        apply()
    }

    private func apply() {
        guard let window else { return }
        let shouldHold = !claims.isEmpty && !Self.tilingModifiersAreHeld
        guard shouldHold != holdsWindow else { return }
        holdsWindow = shouldHold
        guard shouldHold else {
            window.isMovable = restoredMovability
            return
        }
        restoredMovability = window.isMovable
        window.isMovable = false
        // Flush immediately so the window server clears the drag strip before the next press.
        CATransaction.flush()
    }

    private static func watchTilingModifiers() {
        guard modifierMonitor == nil else { return }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated {
                tilingModifiersChanged(to: event.modifierFlags)
            }
            return event
        }
    }

    private static func tilingModifiersChanged(to flags: NSEvent.ModifierFlags) {
        let areHeld = flags.intersection(.deviceIndependentFlagsMask).isSuperset(of: tilingModifiers)
        guard areHeld != tilingModifiersAreHeld else { return }
        tilingModifiersAreHeld = areHeld
        for case let guarding as BrowserWindowTitleBarGuard in guards.objectEnumerator() ?? NSEnumerator() {
            guarding.apply()
        }
    }
}
