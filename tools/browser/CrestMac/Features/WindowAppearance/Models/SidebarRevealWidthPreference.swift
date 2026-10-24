import CoreGraphics

/// How wide the strip along the window edge is that previews a hidden sidebar
/// when the pointer rests on it.
enum SidebarRevealWidthPreference {
    static let key = "crest.appearance.sidebar-reveal-width"
    static let range: ClosedRange<Double> = 1...24
    static let defaultValue = Double(BrowserCollapsedSidebarRevealMetrics.pointer.width)

    /// A stored value clamped to what the strip can usefully be, so a stale or
    /// hand-edited default never produces an unreachable or page-covering strip.
    static func width(_ stored: Double) -> CGFloat {
        CGFloat(min(max(stored.rounded(), range.lowerBound), range.upperBound))
    }
}
