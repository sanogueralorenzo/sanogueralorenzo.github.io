import CoreGraphics

/// The geometry of the Site Controls popover, its trigger and its rows.
enum BrowserSiteControlMetrics {
    static let width: CGFloat = 292
    static let expandedHeight: CGFloat = 520
    static let maximumHeight: CGFloat = 560
    static let quickActionHeight: CGFloat = 34
    static let quickActionGlyphSize: CGFloat = 13
    static let extensionActionHeight: CGFloat = 34
    static let extensionGlyphSize: CGFloat = 17
    static let extensionColumnCount = 4
    static let extensionGridSpacing: CGFloat = 6
    static let manageExtensionControlSize: CGFloat = 20
    static let triggerSize = CGSize(
        width: BrowserTabTrailingControlMetrics.pointer.controlSize.height,
        height: BrowserTabTrailingControlMetrics.pointer.controlSize.height
    )
}
