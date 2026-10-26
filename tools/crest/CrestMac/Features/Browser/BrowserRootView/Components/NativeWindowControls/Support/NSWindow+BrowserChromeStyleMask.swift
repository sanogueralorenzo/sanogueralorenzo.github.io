import AppKit

/// What a browser window's chrome shows for the style AppKit gave the window.
extension NSWindow.StyleMask {
    // MARK: - Variables

    /// Whether the chrome's toolbar shows: never in native fullscreen, which
    /// supplies its own top bar.
    var showsBrowserToolbar: Bool {
        !contains(.fullScreen)
    }

    // MARK: - Actions - Chrome

    /// A collapsed sidebar owns no place for window controls in ordinary
    /// windowed chrome. Native fullscreen supplies its own top bar, so those
    /// standard controls remain available there regardless of sidebar state.
    func showsWindowControls(sidebarPresentationShowsControls: Bool) -> Bool {
        sidebarPresentationShowsControls || contains(.fullScreen)
    }

    /// How far the window controls move to sit over a sidebar on the right.
    /// Fullscreen owns their placement.
    func windowControlsSidebarOffset(windowWidth: CGFloat, sidebarWidth: CGFloat) -> CGFloat {
        guard !contains(.fullScreen) else { return 0 }
        return Swift.max(0, windowWidth - sidebarWidth)
    }

    /// The style a window returns to when Crest's chrome leaves it. AppKit
    /// owns the fullscreen bit and changes it only in its own transitions, so
    /// a window left while in fullscreen, or first met there, keeps the state
    /// AppKit gave it.
    func restoringBrowserChrome(to original: NSWindow.StyleMask) -> NSWindow.StyleMask {
        original.subtracting(.fullScreen).union(intersection(.fullScreen))
    }
}
