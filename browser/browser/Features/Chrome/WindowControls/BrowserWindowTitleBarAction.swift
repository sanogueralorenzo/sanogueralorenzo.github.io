import AppKit

/// Match the native title-bar double-click preference in System Settings.
struct BrowserWindowTitleBarAction: Hashable, Sendable {

    /// Use zoom as the fallback when fill tiling is unavailable.
    static let fill = BrowserWindowTitleBarAction(name: "Fill", selectors: ["_zoomFill:", "performZoom:"])
    static let zoom = BrowserWindowTitleBarAction(name: "Maximize", selectors: ["performZoom:"])
    static let minimize = BrowserWindowTitleBarAction(name: "Minimize", selectors: ["performMiniaturize:"])
    static let none = BrowserWindowTitleBarAction(name: "None", selectors: [])
    static let all: [BrowserWindowTitleBarAction] = [fill, zoom, minimize, none]

    private static let preferenceKey = "AppleActionOnDoubleClick"

    let name: String
    private let selectors: [String]

    /// Zoom matches the native default when no preference has been stored.
    static func current(in defaults: UserDefaults = .standard) -> BrowserWindowTitleBarAction {
        named(defaults.string(forKey: preferenceKey)) ?? zoom
    }

    static func named(_ name: String?) -> BrowserWindowTitleBarAction? {
        all.first { $0.name == name }
    }

    @MainActor func perform(on window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
            let selector = selectors.lazy.map(NSSelectorFromString).first(where: window.responds(to:))
        else { return }
        window.perform(selector, with: nil)
    }
}
