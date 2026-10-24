import AppKit
import QuartzCore

/// Keeps the window server from dragging a window by a page under its title bar.
///
/// A movable window hands the window server the whole strip under its title bar,
/// and the window server drags the window from it before the app sees a press.
/// SwiftUI claims none of that strip for the pages it hosts when the window's
/// content extends under the title bar, so a press at the very top of a page
/// would move the window. While the pointer is on a page there
/// (`BrowserPageTitleBarTracker`), the window is not movable and the window
/// server has no strip to drag from. Everywhere else it stays movable, so the
/// Window menu's Move & Resize, the green button's tiling, the Globe-Control
/// tiling keys and a display change all still move it. Holding Globe and
/// Control hands the window back for those keys even while the pointer is on a
/// page's top.
@MainActor
final class BrowserWindowTitleBarGuard {
    // MARK: - Static Variables

    private static let guards = NSMapTable<NSWindow, BrowserWindowTitleBarGuard>.weakToStrongObjects()
    /// The modifiers every system window-tiling key shares.
    private static let tilingModifiers: NSEvent.ModifierFlags = [.function, .control]
    private static var tilingModifiersAreHeld = false
    private static var modifierMonitor: Any?

    // MARK: - Variables

    private weak var window: NSWindow?
    /// The pages that have the pointer on them under the title bar.
    private var claims: Set<ObjectIdentifier> = []
    /// Whether the window was movable before this guard held it.
    private var restoredMovability = true
    /// Whether this guard has made the window unmovable.
    private var holdsWindow = false

    // MARK: - Initializers

    private init(window: NSWindow) {
        self.window = window
    }

    // MARK: - Actions - Claims

    /// The guard of `window`, made the first time a page asks for it.
    static func guarding(_ window: NSWindow) -> BrowserWindowTitleBarGuard {
        if let existing = guards.object(forKey: window) { return existing }
        let created = BrowserWindowTitleBarGuard(window: window)
        guards.setObject(created, forKey: window)
        watchTilingModifiers()
        return created
    }

    /// `page` has the pointer on it under the title bar.
    func claim(by page: AnyObject) {
        guard claims.insert(ObjectIdentifier(page)).inserted else { return }
        apply()
    }

    /// `page` no longer has the pointer on it under the title bar.
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
        // AppKit sends the window server its new, empty strip when it next
        // flushes the window. Flushing now, rather than at the end of this turn
        // of the run loop, keeps a press that follows at once from beating it.
        CATransaction.flush()
    }

    // MARK: - Actions - Tiling Keys

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
