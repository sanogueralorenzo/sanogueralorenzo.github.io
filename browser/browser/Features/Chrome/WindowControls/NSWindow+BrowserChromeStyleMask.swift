import AppKit

extension NSWindow.StyleMask {

    /// Preserve the fullscreen bit because AppKit owns that transition.
    func restoringBrowserChrome(to original: NSWindow.StyleMask) -> NSWindow.StyleMask {
        original.subtracting(.fullScreen).union(intersection(.fullScreen))
    }
}
