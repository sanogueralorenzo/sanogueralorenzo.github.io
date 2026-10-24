import CoreGraphics

/// The divider affordance's own numbers, kept beside it the way
/// `BrowserSidebarResizeHandleMetrics` sits beside the sidebar's handle.
///
/// The indicator deliberately matches the sidebar's capsule: Crest has exactly
/// two resize affordances and they should not read as two different controls.
enum BrowserSplitCardResizeHandleMetrics {
    static let indicatorWidth: CGFloat = 2
    static let indicatorHeight: CGFloat = 46
    static let activeIndicatorOpacity = 0.28

    /// How far one accessibility increment moves the divider. Larger than the
    /// sidebar's step because a column boundary travels across a whole page
    /// rather than a fixed-range sidebar.
    static let accessibilityStep: CGFloat = 24
}
