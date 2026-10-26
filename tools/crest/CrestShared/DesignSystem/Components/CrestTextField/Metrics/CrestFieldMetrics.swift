import CoreGraphics

/// The single field treatment: one radius, one hairline, and one focus ring.
enum CrestFieldMetrics {
    static let cornerRadius: CGFloat = CrestRadius.control
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = CrestSpacing.medium
    static let borderWidth: CGFloat = CrestLayout.hairline
    static let focusRingWidth: CGFloat = CrestLayout.focusRing
    static let focusRingOpacity = 0.32
}
