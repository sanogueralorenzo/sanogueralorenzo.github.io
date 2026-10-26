import AppKit

@MainActor
enum BrowserMacDownloadFeedbackSource {
    /// Read the pointer only when an engine hands us a real download. This is
    /// presentation geometry, never proof of a trusted user gesture.
    static func capture(in pageView: NSView) -> BrowserDownloadFeedbackSource? {
        guard let window = pageView.window,
            window.isKeyWindow,
            window.isVisible,
            !pageView.isHiddenOrHasHiddenAncestor,
            let content = window.contentView
        else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = content.convert(pointInWindow, from: nil)
        guard content.bounds.contains(point) else { return nil }
        return BrowserDownloadFeedbackSource(
            pointInGlobal: CGPoint(
                x: point.x - content.bounds.minX,
                y: content.isFlipped ? point.y - content.bounds.minY : content.bounds.maxY - point.y
            ),
            windowIdentifier: ObjectIdentifier(window)
        )
    }
}
