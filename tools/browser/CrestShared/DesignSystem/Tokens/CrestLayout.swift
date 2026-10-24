import CoreGraphics

/// Cross-feature geometry that represents an interaction contract.
enum CrestLayout {
    static let hairline: CGFloat = 1
    static let focusRing: CGFloat = 3
    /// Default drawn diameter for stand-alone Liquid Glass icon controls.
    static let glassIconButtonDiameter: CGFloat = 44
    static let sidebarControlCornerRadius = CrestRadius.compact
    static let reloadQuarterTurn: CGFloat = 90
    static let pinnedAccentBorderWidth: CGFloat = 2

    static let minimumHitTarget = CrestPlatformLayout.minimumHitTarget
    static let sidebarRowHeight = CrestPlatformLayout.sidebarRowHeight
}
