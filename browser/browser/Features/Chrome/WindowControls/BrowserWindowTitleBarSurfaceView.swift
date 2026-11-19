import AppKit

/// Handle drags where AppKit does not, including when a page holds the window still.
@MainActor
final class BrowserWindowTitleBarSurfaceView: NSView {

    /// Allow a drag on the first click even when the window is inactive.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 {
            BrowserWindowTitleBarAction.current().perform(on: window)
        } else {
            window.performDrag(with: event)
        }
    }
}
