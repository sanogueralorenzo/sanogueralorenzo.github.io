import SwiftUI

/// Where a tab's status badge hangs when it sits beside the favicon rather
/// than in its place.
///
/// A row hangs the badge off the favicon's corner, in place of its engine
/// badge. A pinned tile holds its favicon in the middle, where a badge would
/// cover the very spot people press to open the tab, so it puts the badge in
/// the tile's own bottom trailing corner and leaves the engine badge where it
/// is.
struct BrowserTabStatusBadgeAnchor: Sendable {
    // MARK: - Static Variables

    /// The favicon's bottom trailing corner, in place of its engine badge.
    static let favicon = BrowserTabStatusBadgeAnchor(takesFaviconCorner: true) { icon, _, diameter, scale, _ in
        let inset = diameter / 2 - TabFaviconBadge.overhang * scale
        return CGPoint(x: icon.maxX - inset, y: icon.maxY - inset)
    }

    /// The bottom trailing corner of the tile itself, clear of the favicon.
    /// The badge is centered on the corner's curve, so it sits as far from
    /// the bottom as from the side and follows the corner setting; a square
    /// or barely rounded tile still keeps it ``minimumTileGap`` off its edges.
    static let tile = BrowserTabStatusBadgeAnchor(takesFaviconCorner: false) { _, tile, diameter, scale, cornerRadius in
        let inset = max(cornerRadius, diameter / 2 + minimumTileGap * scale)
        return CGPoint(x: tile.width - inset, y: tile.height - inset)
    }

    /// The least space a tile's badge keeps from the tile's edges.
    private static let minimumTileGap: CGFloat = 6

    // MARK: - Variables

    /// Whether the badge takes the favicon corner the engine badge would use,
    /// so the engine badge steps aside.
    let takesFaviconCorner: Bool

    /// The badge's center, from the favicon's frame, the size of the row or
    /// tile, the badge's diameter, the person's icon scale and the corner
    /// radius sidebar layers wear.
    let center:
        @Sendable (
            _ icon: CGRect, _ container: CGSize, _ diameter: CGFloat, _ scale: CGFloat, _ cornerRadius: CGFloat
        ) -> CGPoint
}
