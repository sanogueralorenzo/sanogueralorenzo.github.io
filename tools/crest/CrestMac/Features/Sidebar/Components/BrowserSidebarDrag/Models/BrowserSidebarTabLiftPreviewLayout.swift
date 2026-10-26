import CoreGraphics

/// A lifted tab's art, which takes the shape it is morphing into.
struct BrowserSidebarTabLiftPreviewLayout: BrowserSidebarLiftPreviewLayout {
    // MARK: - Actions - Layout

    func artSize(of lift: BrowserSidebarFloatingLift, rowWidth: CGFloat, pinnedSize: CGSize) -> CGSize {
        lift.shape.size(rowWidth: rowWidth, pinnedSize: pinnedSize)
    }
}
