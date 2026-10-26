import AppKit

/// How a window the shell opens, or one already open, comes forward.
@MainActor
struct BrowserMacWindowActivation {
    // MARK: - Static Variables

    /// The window becomes key and comes to the front.
    static let key = BrowserMacWindowActivation { window in window.makeKeyAndOrderFront(nil) }
    /// The window comes forward just behind the key window, which stays key,
    /// and the app stays active or inactive as it was: a window an extension
    /// opened without focus, or one a launch restores behind the front one.
    static let background = BrowserMacWindowActivation { window in
        if let key = NSApp.keyWindow, key !== window, key.isVisible {
            window.order(.below, relativeTo: key.windowNumber)
        } else {
            window.orderFront(nil)
        }
    }

    // MARK: - Variables

    private let bringForward: @MainActor (NSWindow) -> Void

    // MARK: - Initializers

    private init(bringForward: @escaping @MainActor (NSWindow) -> Void) {
        self.bringForward = bringForward
    }

    // MARK: - Actions - Presenting

    /// Brings `window` forward as this activation says.
    func present(_ window: NSWindow) {
        bringForward(window)
    }
}
