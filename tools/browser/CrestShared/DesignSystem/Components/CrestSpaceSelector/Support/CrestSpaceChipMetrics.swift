import CoreGraphics

/// Shared measurements for Space chips and their rail.
enum CrestSpaceChipMetrics {
    static let baseHeight: CGFloat = 42
    static var height: CGFloat { max(baseHeight, CrestLayout.minimumHitTarget) }
    static let cornerRadius: CGFloat = CrestRadius.control
    static let horizontalPadding: CGFloat = CrestSpacing.medium
    static let contentSpacing: CGFloat = CrestSpacing.small
    static let railSpacing: CGFloat = CrestSpacing.small
    static let iconSize: CGFloat = 24
    static let menuIconSize: CGFloat = 20
    static var lockSize: CGFloat { max(5, iconSize * 0.24) }
    static let selectedStrokeWidth: CGFloat = CrestButtonMetrics.prominentStrokeWidth
    static let restingStrokeWidth: CGFloat = CrestButtonMetrics.quietStrokeWidth
    static let selectedStrokeOpacity = 0.72
    static let dashPattern: [CGFloat] = [6, 5]
}
