import CoreGraphics

/// A lifted split group's art: a row whose drawing grows by its member lines.
struct BrowserSidebarSplitLiftPreviewLayout: BrowserSidebarLiftPreviewLayout {
    // MARK: - Variables

    /// How many tabs the split holds.
    let memberCount: Int

    // MARK: - Actions - Layout

    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize {
        let rowSize = BrowserTabDragPreviewLayout.rowSize
        return CGSize(width: base.width, height: max(base.height, CGFloat(memberCount + 1) * rowSize.height))
    }
}
