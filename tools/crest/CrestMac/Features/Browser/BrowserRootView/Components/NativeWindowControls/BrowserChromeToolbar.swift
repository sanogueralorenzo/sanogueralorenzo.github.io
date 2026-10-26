import AppKit

/// The toolbar that holds a browser window's title bar metrics, which shows
/// only outside fullscreen whoever asks it to.
///
/// SwiftUI shows a window's toolbar again whenever the window's content
/// changes its bar preferences, and presenting a popover is such a change.
/// AppKit closes every popover a window shows as that window's toolbar shows,
/// so in fullscreen, where this toolbar is hidden, a popover such as Site
/// Controls closed the moment it opened. The toolbar declines to show there
/// instead, and nothing reaches the popovers.
@MainActor
final class BrowserChromeToolbar: NSToolbar {
    // MARK: - Static Variables

    static let chromeIdentifier = NSToolbar.Identifier("crest.browser.window-chrome")

    // MARK: - Variables

    /// The window whose title bar the toolbar measures.
    weak var chromeWindow: NSWindow?

    override var isVisible: Bool {
        get { super.isVisible }
        set {
            guard !newValue || showsInChromeWindow else { return }
            super.isVisible = newValue
        }
    }

    /// Whether the toolbar may show in its window as the window is now.
    private var showsInChromeWindow: Bool {
        guard let chromeWindow else { return true }
        return chromeWindow.styleMask.showsBrowserToolbar
    }
}
