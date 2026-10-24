import CoreGraphics

/// A lifted selection's art: its rows, which never scale and keep the grab
/// where it was, both where they were and gathered under it.
struct BrowserSidebarSelectionLiftPreviewLayout: BrowserSidebarLiftPreviewLayout {
    // MARK: - Variables

    let rows: [BrowserSidebarSelectionPreviewRow]

    // MARK: - Actions - Layout

    /// Where the selection was grabbed.
    func displayAnchor(of lift: BrowserSidebarFloatingLift, artSize: CGSize) -> CGSize {
        lift.grabOffset
    }

    /// A selection is never scaled.
    func scale(artSize: CGSize, landedFrame: CGRect?, reduceMotion: Bool) -> CGSize {
        CGSize(width: 1, height: 1)
    }

    /// A selection keeps its grab on the lead row of its gathered stack.
    func landedPointer(of lift: BrowserSidebarFloatingLift, in landedFrame: CGRect, pinnedSize: CGSize) -> CGPoint {
        let leadOffset = BrowserSidebarSelectionPreviewRow.stackOffset(
            of: lift.item.id, in: rows, shape: lift.shape, pinnedSize: pinnedSize)
        return CGPoint(
            x: landedFrame.minX + lift.grabOffset.width,
            y: landedFrame.minY + leadOffset + lift.grabOffset.height)
    }

    /// The rows both where they were and gathered under the grab.
    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize {
        let rowSize = BrowserTabDragPreviewLayout.rowSize
        guard let lead = rows.first(where: { $0.id == lift.item.id }) ?? rows.first else { return base }
        var (width, height) = (base.width, base.height)
        var gatheredHeight: CGFloat = 0
        for row in rows {
            let rowWidth = max(
                BrowserTabDragPreviewLayout.resolvedRowWidth(lift.rowWidth), row.frame.width,
                lift.pinnedTileSize.width)
            let rowHeight = max(
                row.frame.height, rowSize.height, lift.pinnedTileSize.height,
                row.isSplit ? CGFloat(row.tabs.count + 1) * rowSize.height : 0)
            gatheredHeight += rowHeight
            width = max(width, abs(row.frame.minX - lead.frame.minX) + rowWidth)
            height = max(height, abs(row.frame.minY - lead.frame.minY) + rowHeight)
        }
        width += abs(lift.grabOffset.width)
        height = max(height, gatheredHeight) + abs(lift.grabOffset.height)
        return CGSize(width: width, height: height)
    }
}
