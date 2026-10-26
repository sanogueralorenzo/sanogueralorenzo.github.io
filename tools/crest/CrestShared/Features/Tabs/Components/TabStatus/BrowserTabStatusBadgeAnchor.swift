import SwiftUI

/// Where a tab's status badge hangs when it sits beside the favicon rather
/// than in its place.
///
/// Rows and pinned chips hang the badge off the favicon's corner, in place of
/// its engine badge, leaving the title and activation area clear.
struct BrowserTabStatusBadgeAnchor: Sendable {
    // MARK: - Static Variables

    /// The favicon's bottom trailing corner, in place of its engine badge.
    static let favicon = BrowserTabStatusBadgeAnchor(takesFaviconCorner: true) { icon, _, diameter, scale, _ in
        let inset = diameter / 2 - TabFaviconBadge.overhang * scale
        return CGPoint(x: icon.maxX - inset, y: icon.maxY - inset)
    }

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
