import CoreGraphics

/// Shared dimensions for the gradient dial, palette, and setup preview.
enum BrowserSpaceForgeMetrics {

    static let previewIdentitySize: CGFloat = 40

    static let gradientNeedleLengthRatio: CGFloat = 0.37
    static let gradientNeedleThicknessRatio: CGFloat = 0.035
    static let gradientNeedleOffsetRatio: CGFloat = 0.185
    static let gradientNeedleMinimumThickness: CGFloat = 2
    static let gradientCenterDiameterRatio: CGFloat = 0.075
    static let gradientCenterMinimumDiameter: CGFloat = 5
    static let gradientFocusRingWidth: CGFloat = 2
    static let gradientFocusRingInset: CGFloat = 2

    static let paletteLabelMinimumScale: CGFloat = 0.8

    static let angleCircleDegrees = 360.0
    static let radiansToDegrees = 180.0

}
