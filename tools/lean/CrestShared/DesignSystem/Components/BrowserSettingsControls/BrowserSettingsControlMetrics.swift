import CoreGraphics

/// The shared geometry and fills of the settings icon and labeled action buttons.
enum BrowserSettingsControlMetrics {
    static let minimumTouchTarget: CGFloat = 44
    static let labeledActionHeight: CGFloat = 46
    static let horizontalPadding = CrestSpacing.medium
    static let cornerRadius: CGFloat = 10
    static let borderWidth = CrestLayout.hairline
    static let restingFillOpacity = 0.08
    static let labeledPressedFillOpacity = 0.16
    static let labeledBorderOpacity = 0.24
    static let labeledPressedScale: CGFloat = 0.985
    static let labeledDisabledOpacity = 0.42
    static let iconPressedFillOpacity = 0.18
    static let iconPressedScale: CGFloat = 0.94
    static let iconDisabledOpacity = 0.34
}
