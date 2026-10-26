import CoreGraphics

/// How the art of one kind of lift preview subject is sized, anchored, scaled
/// and placed. The defaults are a row's: the width of a folder row and the
/// height of its source, held at the lift's anchor, scaled to fill where it
/// lands and by the lift's rise while it is held. A kind that differs says so.
protocol BrowserSidebarLiftPreviewLayout {
    /// The size the art is laid out at for `lift`, before any scaling.
    func artSize(of lift: BrowserSidebarFloatingLift, rowWidth: CGFloat, pinnedSize: CGSize) -> CGSize

    /// The point of the art of `artSize` that stays under the pointer.
    func displayAnchor(of lift: BrowserSidebarFloatingLift, artSize: CGSize) -> CGSize

    /// How much the art of `artSize` is scaled.
    func scale(artSize: CGSize, landedFrame: CGRect?, reduceMotion: Bool) -> CGSize

    /// Where the art of `lift` is drawn once it lands in `landedFrame`.
    func landedPointer(of lift: BrowserSidebarFloatingLift, in landedFrame: CGRect, pinnedSize: CGSize) -> CGPoint

    /// The extent the preview window covers for the art of `lift`, grown from
    /// `base`, the envelope of every shape a lifted row takes.
    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize
}

extension BrowserSidebarLiftPreviewLayout {
    // MARK: - Actions - Layout

    func artSize(of lift: BrowserSidebarFloatingLift, rowWidth: CGFloat, pinnedSize: CGSize) -> CGSize {
        CGSize(width: BrowserFolderDragPreviewLayout.width(for: rowWidth), height: max(lift.sourceSize.height, 1))
    }

    func displayAnchor(of lift: BrowserSidebarFloatingLift, artSize: CGSize) -> CGSize {
        CGSize(width: lift.anchorFraction.x * artSize.width, height: lift.anchorFraction.y * artSize.height)
    }

    /// Scaled to fill `landedFrame` once it lands, and by the lift's rise
    /// while it is held.
    func scale(artSize: CGSize, landedFrame: CGRect?, reduceMotion: Bool) -> CGSize {
        if let landedFrame {
            return CGSize(
                width: landedFrame.width / max(artSize.width, 1),
                height: landedFrame.height / max(artSize.height, 1))
        }
        let value = BrowserSidebarReorderVisuals.liftScale.unlessReducingMotion(reduceMotion)
        return CGSize(width: value, height: value)
    }

    func landedPointer(of lift: BrowserSidebarFloatingLift, in landedFrame: CGRect, pinnedSize: CGSize) -> CGPoint {
        CGPoint(
            x: landedFrame.minX + lift.anchorFraction.x * landedFrame.width,
            y: landedFrame.minY + lift.anchorFraction.y * landedFrame.height)
    }

    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize {
        base
    }
}
