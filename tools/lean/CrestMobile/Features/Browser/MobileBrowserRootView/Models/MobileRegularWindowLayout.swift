import CoreGraphics
import SwiftUI

/// How a regular window fits its sidebar: beside the page when the page
/// keeps a usable width, and otherwise over it. Across a fold, the sidebar
/// keeps to one side of it and the page to the other, or floats over a split
/// whose pages take a side each.
struct MobileRegularWindowLayout: Equatable, Sendable {
    // MARK: - Static Variables

    /// Leaves enough room for an actually usable web viewport while retaining
    /// the iPad sidebar anatomy for every ordinary Stage Manager width.
    static let minimumDetailWidth: CGFloat = 320
    static let overlayEdgeClearance: CGFloat = 44

    // MARK: - Variables

    let sidebarWidth: CGFloat

    /// How much of the window's width the page leaves the sidebar: its own
    /// width, and the fold beside it while the sidebar keeps to the fold's
    /// other side.
    let reservedSidebarWidth: CGFloat

    /// Whether the sidebar sits beside the page, taking its width from it,
    /// rather than over it.
    let reservesSidebarWidth: Bool

    /// Whether a fold, rather than the person, sets the sidebar's width.
    let followsFold: Bool

    /// Whether a fold divides a split's pages, a side each.
    let splitsPagesAtFold: Bool

    /// Whether the sidebar runs up to the window's top edge: a foldable
    /// display held upright keeps a band across its top for the status bar
    /// and a top bar, and the status bar takes only its far end.
    let runsSidebarToTopEdge: Bool

    // MARK: - Initializers

    /// - Parameters:
    ///   - foldSpan: Where a fold crosses the window, from its leading edge.
    ///   - sidebarEdge: The window edge the sidebar keeps to.
    ///   - presentsColumns: Whether the page is a split, whose pages take the
    ///     fold's two sides.
    ///   - sharesTopBandWithStatusBar: Whether the display keeps a top band
    ///     the status bar shares with a top bar.
    init(
        availableWidth: CGFloat,
        preferredSidebarWidth: CGFloat,
        foldSpan: ClosedRange<CGFloat>? = nil,
        sidebarEdge: HorizontalEdge = .leading,
        presentsColumns: Bool = false,
        sharesTopBandWithStatusBar: Bool = false
    ) {
        runsSidebarToTopEdge = sharesTopBandWithStatusBar
        splitsPagesAtFold = foldSpan != nil && presentsColumns
        let availableWidth = max(0, availableWidth)
        let preferredSidebarWidth = BrowserChromeLayout.clampedSidebarWidth(
            preferredSidebarWidth
        )

        if let foldSpan, !presentsColumns {
            let sideWidth =
                sidebarEdge == .leading
                ? foldSpan.lowerBound
                : availableWidth - foldSpan.upperBound
            let reservedWidth =
                sidebarEdge == .leading
                ? foldSpan.upperBound
                : availableWidth - foldSpan.lowerBound
            if sideWidth >= BrowserChromeLayout.sidebarMinimumWidth {
                sidebarWidth = sideWidth
                reservedSidebarWidth = reservedWidth
                reservesSidebarWidth = true
                followsFold = true
                return
            }
        }

        let sideBySideLimit = availableWidth - Self.minimumDetailWidth
        if foldSpan == nil, sideBySideLimit >= BrowserChromeLayout.sidebarMinimumWidth {
            sidebarWidth = min(preferredSidebarWidth, sideBySideLimit)
            reservedSidebarWidth = sidebarWidth
            reservesSidebarWidth = true
            followsFold = false
            return
        }

        sidebarWidth = min(
            preferredSidebarWidth,
            max(0, availableWidth - Self.overlayEdgeClearance)
        )
        reservedSidebarWidth = sidebarWidth
        reservesSidebarWidth = false
        followsFold = foldSpan != nil
    }
}
