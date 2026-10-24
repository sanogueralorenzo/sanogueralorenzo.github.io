import Foundation

/// Native actions supplied by the platform shell to a Space header.
struct BrowserSpaceHeaderActions {
    /// Opens a new tab in this Space.
    let openNewTab: () -> Void

    /// Opens another window on the same session. Gated a second time at the
    /// menu on `\.supportsMultipleWindows`, because a scene can be configured
    /// for a single window even where the shell knows how to open more.
    var openNewWindow: (() -> Void)?

    /// Creates a folder in this Space's saved tabs.
    let createFolder: () -> Void

    /// Opens the history list.
    let showHistory: () -> Void

    /// Opens saved passwords. Nil where the shell reaches them elsewhere.
    /// Where it is present and private browsing is on, the item becomes the
    /// disabled note that says why.
    var showPasswords: (() -> Void)?

    /// Closes every private tab. Rendered only while private browsing is on,
    /// since it is the one action that has nothing to act on otherwise.
    var closePrivateBrowsing: (() -> Void)?

    /// Opens settings. Nil where the shell has its own settings entry point.
    var showSettings: (() -> Void)?

    /// Closes the Space's current tabs, leaving the saved ones alone.
    let cleanup: () -> Void

    /// Toggles live expansion when the header renders a retained page value.
    var toggleSavedTabs: (() -> Void)?
}
