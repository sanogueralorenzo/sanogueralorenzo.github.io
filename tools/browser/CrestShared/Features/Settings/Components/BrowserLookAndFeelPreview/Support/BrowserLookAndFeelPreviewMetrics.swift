import CoreGraphics

/// Measurements for the Look and Feel previews.
enum BrowserLookAndFeelPreviewMetrics {
    /// The least page a crop may show beside the sidebar: enough to read the
    /// window border, the page corner, and the seam between them. Wider crops
    /// give every extra point to the page, as a wider window would.
    static let pageMinimumWidth: CGFloat = 72
    static let pageZoom = 0.7
    /// The crop's height when it sits at the top of a card rather than filling
    /// a pinned column.
    static let inlineCropHeight: CGFloat = 300
    static let cardCornerRadius = CrestRadius.card
    /// A friendly stand-in. The preview never shows the address being browsed.
    static let sampleAddress = "https://example.com/reading-list"
}
