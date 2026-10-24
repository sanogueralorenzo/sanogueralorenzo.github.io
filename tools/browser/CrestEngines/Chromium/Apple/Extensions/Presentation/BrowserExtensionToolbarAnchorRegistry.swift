import AppKit

/// Where an extension popup opens when nothing was clicked.
///
/// An `_execute_action` keyboard shortcut runs through the core so the popup
/// keeps the anchor a click would have used — but a shortcut has no pointer
/// location, and the pointer is very often nowhere near the browser chrome.
/// The controls that stand for an extension action register themselves here as
/// they appear, so the shortcut can resolve the same control a click on the
/// extension's own button would have anchored to.
///
/// Registrations are per window and weakly held: a control that leaves the view
/// hierarchy stops being an answer, and the registry never keeps one alive.
@MainActor
enum BrowserExtensionToolbarAnchorRegistry {
    enum Site: Hashable {
        /// The extension's own tile in the window's pinned strip.
        case tile(String)
        /// The control that opens the window's extension list.
        case menu
    }

    private final class Entry {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private static var entries: [Site: [Entry]] = [:]

    static func register(_ view: NSView, as site: Site) {
        var sited = entries[site, default: []].filter { $0.view != nil && $0.view !== view }
        sited.append(Entry(view))
        entries[site] = sited
    }

    static func unregister(_ view: NSView, as site: Site) {
        let sited = entries[site, default: []].filter { $0.view != nil && $0.view !== view }
        entries[site] = sited.isEmpty ? nil : sited
    }

    /// The anchor for `extensionID` in `window`: its pinned tile when the strip
    /// is showing one, otherwise the control that opens the extension list.
    /// `nil` when the window is showing neither, which leaves the caller its
    /// own fallback.
    static func anchor(
        for extensionID: String,
        in window: NSWindow?
    ) -> BrowserExtensionPopupAnchor? {
        guard let window else { return nil }
        let view =
            resolve(.tile(extensionID), in: window)
            ?? resolve(.menu, in: window)
        return view.map(BrowserExtensionPopupAnchor.init(sourceView:))
    }

    private static func resolve(_ site: Site, in window: NSWindow) -> NSView? {
        entries[site]?.lazy.compactMap(\.view).first {
            $0.window === window && !$0.isHiddenOrHasHiddenAncestor
        }
    }
}
