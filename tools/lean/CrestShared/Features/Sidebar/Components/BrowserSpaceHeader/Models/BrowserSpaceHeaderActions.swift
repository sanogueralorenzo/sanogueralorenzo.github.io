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

    /// Adds the GitHub live folder where the shell can refresh website sessions.
    var createGitHubFolder: (() -> Void)?

    /// Opens the history list.
    let showHistory: () -> Void

    var showArchive: (() -> Void)?
    var showDownloads: (() -> Void)?
    var showTabs: (() -> Void)?
    var showWebsiteSettings: (() -> Void)?

    /// Closes every private tab. Rendered only while private browsing is on,
    /// since it is the one action that has nothing to act on otherwise.
    var closePrivateBrowsing: (() -> Void)?

    /// Opens the browser settings.
    var showSettings: (() -> Void)?

    /// The shell's application-level shortcut, when Settings has one.
    var settingsShortcut: BrowserShortcut?

}
