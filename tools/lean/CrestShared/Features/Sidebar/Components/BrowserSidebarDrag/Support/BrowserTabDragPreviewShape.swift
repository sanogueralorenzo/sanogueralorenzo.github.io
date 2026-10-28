import CoreGraphics

/// The forms a lifted tab can take while a drag is in flight.
///
/// A lift shows what the tab is about to become, so the shape is a property of
/// the destination rather than of the tab: the same row becomes a tile over the
/// pinned grid and a page-shaped card over the content area. Every number a
/// morph interpolates lives here, which is what lets
/// `BrowserTabDragPreviewLayout` interpolate any pair without knowing what
/// either end means. The one number a shape does not own is a sidebar layer's
/// corner, which follows the person's corner setting and is handed in.
enum BrowserTabDragPreviewShape: Equatable, Sendable {
    /// A sidebar list row — the resting shape of every unpinned tab.
    case row
    /// A cell of the pinned grid.
    case pinnedTile
    /// A card in the split-view content area.
    case webpageCard

    /// The shape a tab resting in this placement already has, and therefore the
    /// shape a lift starts from.
    static func resting(for placement: TabPlacement) -> BrowserTabDragPreviewShape {
        placement.isGrid ? .pinnedTile : .row
    }

    func size(rowWidth: CGFloat, pinnedSize: CGSize = BrowserTabDragPreviewLayout.pinnedSize) -> CGSize {
        switch self {
        case .row:
            CGSize(
                width: BrowserTabDragPreviewLayout.resolvedRowWidth(rowWidth),
                height: BrowserTabDragPreviewLayout.rowSize.height
            )
        case .pinnedTile:
            pinnedSize
        case .webpageCard:
            BrowserTabDragPreviewLayout.cardSize
        }
    }

    /// The shape's corner, where `layerCornerRadius` is the corner of the
    /// sidebar layer a row and a pinned tile are drawn as.
    func cornerRadius(layerCornerRadius: CGFloat) -> CGFloat {
        switch self {
        case .row, .pinnedTile: layerCornerRadius
        // A drop preview that reads as a page has to be cornered like one.
        case .webpageCard: BrowserChromeLayout.pageCornerRadius
        }
    }

    /// How visible the row's own title line is. A tile has no room for it.
    var titleOpacity: Double {
        switch self {
        case .row, .webpageCard: 1
        case .pinnedTile: 0
        }
    }

    /// How far the row's leading favicon travels toward the middle: `0` leaves it
    /// at the leading edge, `1` centres it.
    var contentCentering: CGFloat {
        switch self {
        // The card draws its own centred content instead of moving the row's,
        // so the row layout it fades out of stays where it was.
        case .row, .webpageCard: 0
        case .pinnedTile: 1
        }
    }

    /// How much of the card's own centred layout is showing, as opposed to the
    /// row layout it replaces.
    var cardContentWeight: CGFloat {
        switch self {
        case .row, .pinnedTile: 0
        case .webpageCard: 1
        }
    }
}
