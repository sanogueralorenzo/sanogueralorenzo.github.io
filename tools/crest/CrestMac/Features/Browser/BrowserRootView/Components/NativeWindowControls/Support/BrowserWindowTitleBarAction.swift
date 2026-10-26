import AppKit

/// What a double-click on a window's title bar does, as the person chose in
/// System Settings ("Double-click a window's title bar to"). Crest's own window
/// chrome follows the same choice as the title bar AppKit draws.
struct BrowserWindowTitleBarAction: Hashable, Sendable {
    // MARK: - Static Variables

    /// Fills the screen the way the system's tiling does. A system without
    /// window tiling zooms instead.
    static let fill = BrowserWindowTitleBarAction(name: "Fill", selectors: ["_zoomFill:", "performZoom:"])
    static let zoom = BrowserWindowTitleBarAction(name: "Maximize", selectors: ["performZoom:"])
    static let minimize = BrowserWindowTitleBarAction(name: "Minimize", selectors: ["performMiniaturize:"])
    static let none = BrowserWindowTitleBarAction(name: "None", selectors: [])
    static let all: [BrowserWindowTitleBarAction] = [fill, zoom, minimize, none]

    /// The global preference the choice is stored under.
    private static let preferenceKey = "AppleActionOnDoubleClick"

    // MARK: - Variables

    /// The choice's stored spelling.
    let name: String
    /// The window actions that perform the choice, the first one the window
    /// answers winning.
    private let selectors: [String]

    // MARK: - Actions - Choice

    /// The person's current choice. A system that never stored one zooms, as
    /// AppKit's own title bar does.
    static func current(in defaults: UserDefaults = .standard) -> BrowserWindowTitleBarAction {
        named(defaults.string(forKey: preferenceKey)) ?? zoom
    }

    static func named(_ name: String?) -> BrowserWindowTitleBarAction? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Window

    /// Performs the choice on `window`. A window in fullscreen has no title bar
    /// action, as its own title bar has none.
    @MainActor func perform(on window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
            let selector = selectors.lazy.map(NSSelectorFromString).first(where: window.responds(to:))
        else { return }
        window.perform(selector, with: nil)
    }
}
