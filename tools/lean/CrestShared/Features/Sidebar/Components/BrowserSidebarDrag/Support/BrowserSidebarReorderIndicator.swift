import CoreGraphics

/// Where to draw the insertion line during a sidebar reorder, relative to the
/// row that anchors it.
struct BrowserSidebarReorderIndicator: Equatable, Sendable {
    enum Side: Equatable, Sendable {
        case before
        case after
    }

    let side: Side
    /// Grids insert between columns, so the line is vertical on a cell's edge.
    /// Lists insert between rows, so it is horizontal on a row's edge.
    let flowsHorizontally: Bool
}

enum BrowserSidebarReorderIndicatorMetrics {
    static let thickness: CGFloat = 2
    static let inset: CGFloat = 2
    /// Keeps the line clear of the gap's edge so it reads as a seam.
    static let outset: CGFloat = 1
}
