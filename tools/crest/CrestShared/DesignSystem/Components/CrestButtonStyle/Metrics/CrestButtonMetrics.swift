import CoreGraphics

/// Measurements and opacity roles shared by every Crest button treatment.
enum CrestButtonMetrics {
    static let pressedScale: CGFloat = 0.975
    static let disabledOpacity = 0.42

    static let prominentHeight: CGFloat = 40
    static let standardHeight: CGFloat = 38
    static let prominentHorizontalPadding: CGFloat = CrestSpacing.extraLarge
    static let standardHorizontalPadding: CGFloat = CrestSpacing.large
    static let quietHorizontalPadding: CGFloat = CrestSpacing.small

    /// The visible icon diameter and its independently accessible hit target.
    static let iconDiameter: CGFloat = 34

    static let strokeWidth: CGFloat = CrestLayout.hairline
    static let quietStrokeWidth: CGFloat = 0.75
    static let prominentStrokeWidth: CGFloat = 1.25

    static let inkStrokeOpacity = CrestBrandTheme.lineLightOpacity
    static let pressedFillOpacity = 0.8
    static let tintRestFill = 0.10
    static let tintEmphasizedFill = 0.16
    static let tintPressedFill = 0.22
    static let tintRestStroke = 0.28
    static let tintEmphasizedStroke = 0.55

    static let prominentLabelSize: CGFloat = 14
    static let standardLabelSize: CGFloat = 13
}
