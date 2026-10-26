import CoreGraphics

struct BrowserSplitPanelColumn: Equatable {
    let requestedWidth: CGFloat
}

/// A drag is transient. The owning window receives just one durable width on
/// commit, and resize deltas remain relative to where the gesture began.
struct BrowserSplitPanelWidthTransaction: Equatable {
    private(set) var width: CGFloat?
    private var initialWidth: CGFloat?

    mutating func resize(startingAt requestedWidth: CGFloat, delta: CGFloat) {
        let initial = initialWidth ?? BrowserSplitPanelLayoutMetrics.clampedWidth(requestedWidth)
        initialWidth = initial
        width = BrowserSplitPanelLayout.widthAfterResize(initialWidth: initial, delta: delta)
    }

    mutating func commit() -> CGFloat? {
        defer { self = Self() }
        guard let width, width != initialWidth else { return nil }
        return width
    }
}
