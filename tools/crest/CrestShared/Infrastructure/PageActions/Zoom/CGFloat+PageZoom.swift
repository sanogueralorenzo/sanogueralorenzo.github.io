import CoreGraphics

extension CGFloat {
    // MARK: - Static Variables

    /// The levels the page zoom commands step through and Settings offers.
    static let pageZoomLevels: [CGFloat] = [
        0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3,
    ]
    private static let pageZoomTolerance: CGFloat = 0.001

    // MARK: - Variables

    /// The next level up from this page zoom, or this zoom past the last level.
    var pageZoomIncreased: CGFloat {
        Self.pageZoomLevels.first(where: { $0 > self + Self.pageZoomTolerance })
            ?? Swift.max(self, Self.pageZoomLevels[Self.pageZoomLevels.count - 1])
    }

    /// The next level down from this page zoom, or this zoom below the first level.
    var pageZoomDecreased: CGFloat {
        Self.pageZoomLevels.last(where: { $0 < self - Self.pageZoomTolerance })
            ?? Swift.min(self, Self.pageZoomLevels[0])
    }

    /// This page zoom as the person reads it, such as "125%".
    var pageZoomPercentage: String {
        "\(Int((self * 100).rounded()))%"
    }

    // MARK: - Actions - Comparing

    /// Whether this page zoom and `other` are the same level once rounding is set aside.
    func matchesPageZoom(_ other: CGFloat) -> Bool {
        abs(self - other) <= Self.pageZoomTolerance
    }
}
