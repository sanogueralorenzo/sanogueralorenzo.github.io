import AppKit

/// What a browser window's chrome shows for the style AppKit gave the window.
extension NSWindow.StyleMask {
    // MARK: - Actions - Chrome

    /// A collapsed sidebar owns no place for window controls in ordinary
    /// windowed chrome. Native fullscreen supplies its own top bar, so those
    /// standard controls remain available there regardless of sidebar state.
    func showsWindowControls(sidebarPresentationShowsControls: Bool) -> Bool {
        sidebarPresentationShowsControls || contains(.fullScreen)
    }

    /// The style a window returns to when Lean's chrome leaves it. AppKit
    /// owns the fullscreen bit and changes it only in its own transitions, so
    /// a window left while in fullscreen, or first met there, keeps the state
    /// AppKit gave it.
    func restoringBrowserChrome(to original: NSWindow.StyleMask) -> NSWindow.StyleMask {
        original.subtracting(.fullScreen).union(intersection(.fullScreen))
    }
}
