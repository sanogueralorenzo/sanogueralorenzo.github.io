import CoreGraphics

/// Selection-card measurements shared by all artwork-backed choices.
enum CrestSelectableCardMetrics {
    static let selectedBorderWidth: CGFloat = CrestLayout.pinnedAccentBorderWidth
    static let restingBorderWidth: CGFloat = CrestLayout.hairline
    static let cornerRadius: CGFloat = CrestRadius.card
    static let padding: CGFloat = CrestSpacing.large
    static let contentSpacing: CGFloat = CrestSpacing.medium
    static let selectedFillOpacity = CrestButtonMetrics.tintRestFill
    static let checkmarkSize: CGFloat = 20
    static let checkmarkSymbol = "checkmark.circle.fill"
}
