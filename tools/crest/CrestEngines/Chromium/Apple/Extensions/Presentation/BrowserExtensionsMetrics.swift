import CoreGraphics

enum BrowserExtensionsMetrics {
    static let extensionIconSize: CGFloat = 28
    static let installReviewIconSize: CGFloat = 52
    static let expandedContentIndent: CGFloat = 40
    static let extensionIconCornerRadiusRatio: CGFloat = 0.2
    static let extensionIconFallbackPaddingRatio: CGFloat = 0.18
    static let extensionIconDecodedPixelScale: CGFloat = 3
    static let minimumExtensionIconDecodedPixelSize = 64

    static func maximumDecodedPixelSize(for size: CGFloat) -> Int {
        max(
            minimumExtensionIconDecodedPixelSize,
            Int((size * extensionIconDecodedPixelScale).rounded(.up))
        )
    }
}
