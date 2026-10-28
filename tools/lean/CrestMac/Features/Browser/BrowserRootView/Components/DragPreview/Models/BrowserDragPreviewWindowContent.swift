import CoreGraphics

/// What the window-level drag preview is drawing, if anything.
///
/// Two things in this app travel on the pointer and are clipped by everything if
/// the view tree draws them: a lifted sidebar row and a carried Split View card.
/// Both need the same thing — a transparent window ordered above the browser's,
/// so the page's `WKWebView` cannot composite over them — and neither needs one
/// of its own. This is the seam between them: one host, one panel, one lifetime,
/// and a case per kind of thing being carried.
///
/// Equatable so the host can tell a frame that changed something from a frame
/// that changed nothing, and skip the window work for the latter.
enum BrowserDragPreviewWindowContent: Equatable {
    case sidebarLift(BrowserSidebarLiftPreviewContent)
    case splitCardLift(BrowserSplitCardLiftPreviewContent)

    /// A conservative envelope in the source window's top-left coordinates.
    /// Cover both ends of a morph so resizing the native panel cannot clip the
    /// animation, including a selection gathering from its original row offsets.
    var drawingBounds: CGRect {
        switch self {
        case .sidebarLift(let sidebar):
            return sidebar.drawingBounds
        case .splitCardLift(let card):
            let scale = BrowserSidebarReorderVisuals.liftScale
            return CGRect(origin: card.origin, size: card.size)
                .insetBy(
                    dx: -card.size.width * (scale - 1) - 48,
                    dy: -card.size.height * (scale - 1) - 48)
        }
    }
}
