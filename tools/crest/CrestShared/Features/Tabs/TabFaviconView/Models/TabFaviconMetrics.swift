import CoreGraphics

enum TabFaviconMetrics {
    static let defaultSize: CGFloat = 18
    static let emojiSizeRatio: CGFloat = 0.82
    static let emojiMinimumScaleFactor: CGFloat = 0.7
    static let minimumCornerRadius: CGFloat = 2
    static let cornerRadiusRatio: CGFloat = 0.2
    static let decodedPixelScale: CGFloat = 3
    static let minimumDecodedPixelSize = 64
    static let renderedImageScale: CGFloat = 1

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        max(minimumCornerRadius, size * cornerRadiusRatio)
    }

    static func maximumDecodedPixelSize(for size: CGFloat) -> Int {
        max(
            minimumDecodedPixelSize,
            Int((size * decodedPixelScale).rounded(.up))
        )
    }
}
