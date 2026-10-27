import AppKit

/// Empty window chrome that acts as the window's title bar. Like AppKit's own
/// title bar, it answers each mouse-down by its click count: a press starts a
/// window drag, and the second press of a double-click performs the person's
/// title-bar action instead.
///
/// Under the title bar of a movable window, AppKit's own title bar takes a
/// double-click before it reaches the surface, and the window server may
/// already be dragging the window from a press. Starting the drag here too keeps
/// the surface moving the window where AppKit does not: below the title bar,
/// and under it while a page holds the window still
/// (`BrowserWindowTitleBarGuard`).
@MainActor
final class BrowserWindowTitleBarSurfaceView: NSView {
    // MARK: - Actions - Mouse

    /// A press on an inactive window moves it at once, as its title bar does.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // A window in fullscreen has no title bar to stand in for; its own
        // appears in the menu bar's place and moves it.
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 {
            BrowserWindowTitleBarAction.current().perform(on: window)
        } else {
            window.performDrag(with: event)
        }
    }
}
