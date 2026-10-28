import CoreGraphics

/// Lift treatment for a sidebar reorder — the row rises off the list under the
/// pointer, the way a home-screen icon does.
enum BrowserSidebarReorderVisuals {
    /// How far the preview rises. Applied where the preview is drawn, which is
    /// the window-level host rather than the row: the row stands down for the
    /// whole lift. Every drag preview carries its own drop shadow, so the rise
    /// is all that is left to say here.
    static let liftScale: CGFloat = 1.04

    /// Whether the scrolling run of tabs clips its rows while nothing is lifted.
    static let clipsScrollableRegionWhenIdle = true

    /// Whether the list keeps its normal scroll clip while a row is lifted.
    ///
    /// macOS draws the travelling copy in a window-level host, outside this
    /// ScrollView. Unclipping the list cannot help that lift; it only exposes
    /// lazy rows that are scrolled out of view, including expanded saved-folder
    /// children, over the fixed Space header and pinned grid.
    static func clipsScrollableRegion(
        clipsWhenIdle: Bool,
        isDragging _: Bool
    ) -> Bool {
        clipsWhenIdle
    }
}
