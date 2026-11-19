import AppKit

extension NSWindow.StyleMask {

    /// Fullscreen supplies its own title bar when the sidebar is collapsed.
    func showsWindowControls(sidebarPresentationShowsControls: Bool) -> Bool {
        sidebarPresentationShowsControls || contains(.fullScreen)
    }

    /// Preserve the fullscreen bit because AppKit owns that transition.
    func restoringBrowserChrome(to original: NSWindow.StyleMask) -> NSWindow.StyleMask {
        original.subtracting(.fullScreen).union(intersection(.fullScreen))
    }
}
