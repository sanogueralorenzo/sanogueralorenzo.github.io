import AppKit

@MainActor
struct BrowserPagePoolWindowRuntime {
    let browser: BrowserStore
    let pages: BrowserPagePool

    var activeWebContentView: NSView? {
        pages.activePage?.nativeView
    }

    var activeWebContentFrame: CGRect? {
        guard let view = activeWebContentView,
            let window = view.window
        else { return nil }
        let frameInWindow = view.convert(view.bounds, to: nil)
        guard frameInWindow.width > 0, frameInWindow.height > 0 else {
            return nil
        }
        return window.convertToScreen(frameInWindow)
    }
}
