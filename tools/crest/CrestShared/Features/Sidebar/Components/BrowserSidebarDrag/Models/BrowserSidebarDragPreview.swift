import CoreGraphics
import Foundation

/// A lift that has to be drawn by something other than the view tree it came
/// from, together with everything that drawing needs.
///
/// Every promoted lift is one. A lift drawn in the view tree is at the mercy of
/// whatever it happens to be over: the page is a `WKWebView`, an `NSView`
/// subtree inside the same hosting view, and AppKit composites view subtrees
/// above everything SwiftUI draws beside them no matter what `zIndex` they are
/// given — but window chrome, insets, and the bands a view transition passes
/// through clip a travelling preview just as effectively. Handing the preview
/// over part-way through a drag only moves the seam. So the whole pointer-
/// chasing visual, for the whole lift, belongs to a host that paints above the
/// window: see the macOS drag preview window host. What stays in the sidebar is
/// the structure — the gap the lifted row leaves, the neighbours stepping aside,
/// the drop indicator.
///
/// The value is derived from the live drag and nothing else: the state that
/// produced it is still the only source of truth, and a host that renders this
/// is a presentation of that state rather than a second copy of it.
struct BrowserSidebarFloatingLift: Equatable, Sendable {
    /// What is being lifted, so the host can resolve its real row content — a
    /// tab, a folder, or a whole split group.
    let item: BrowserSidebarReorderItem
    /// What the drop would make of it, and how far the morph has gone. Only a
    /// tab ever changes shape; a folder and a group stay rows wherever they go.
    let shape: BrowserTabDragPreviewShape
    let progress: CGFloat
    /// The pointer, in the global space frames are registered in.
    let pointer: CGPoint
    /// Where inside the row the pointer grabbed it.
    let grabOffset: CGSize
    /// The width the row form of the preview is drawn at.
    let rowWidth: CGFloat
    var sourceSize: CGSize = .zero
    var previewRows: [BrowserSidebarReorderRow] = []
    var pinnedTileSize = BrowserTabDragPreviewLayout.pinnedSize
    var sidebarBounds: CGRect?
    var landing: BrowserSidebarReorderLanding?
    var constraintMessage: String?

    /// The Space profile the preview resolves favicons against.
    var profileID: UUID {
        item.spaceAssignment.profileID
    }

    /// The lifted tab, when a tab is what was lifted.
    var tabID: UUID? {
        item.id.tabID
    }

    /// Top-left of the preview, in the same global space as `pointer`.
    var origin: CGPoint {
        CGPoint(x: presentationPointer.x - anchorOffset.width, y: presentationPointer.y - anchorOffset.height)
    }

    var anchorFraction: CGPoint {
        let size = sourceSize == .zero ? BrowserTabDragPreviewLayout.rowSize : sourceSize
        return CGPoint(
            x: min(max(grabOffset.width / max(size.width, 1), 0), 1),
            y: min(max(grabOffset.height / max(size.height, 1), 0), 1))
    }

    var anchorOffset: CGSize {
        guard case .tab = item else { return grabOffset }
        let metrics = BrowserTabDragPreviewLayout.metrics(
            from: .row, to: shape, progress: progress,
            rowWidth: rowWidth, pinnedSize: pinnedTileSize)
        return CGSize(width: anchorFraction.x * metrics.width, height: anchorFraction.y * metrics.height)
    }

    /// A tile at the sidebar's left edge stays visible during a small pointer
    /// overshoot. Leaving the sidebar toward the page remains unconstrained.
    var presentationPointer: CGPoint {
        guard shape == .pinnedTile, let sidebarBounds,
            pointer.x <= sidebarBounds.maxX,
            pointer.x >= sidebarBounds.minX - BrowserSidebarReorderZone.slop
        else { return pointer }
        let leading = sidebarBounds.minX + 2
        let trailing = max(leading, sidebarBounds.maxX - pinnedTileSize.width - 2)
        let x = min(max(pointer.x - anchorOffset.width, leading), trailing) + anchorOffset.width
        return CGPoint(x: x, y: pointer.y)
    }
}

/// A presentation handoff, not another reorder. The model has already moved;
/// the floating component covers its replacement until the animation finishes.
struct BrowserSidebarReorderLanding: Equatable, Sendable {
    var id = UUID()
    var frame: CGRect
    var isRevealing = false
}

/// The measured appearance of a drag preview part-way between two shapes.
struct BrowserTabDragPreviewMetrics: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let titleOpacity: Double
    /// `0` keeps the row's leading favicon at the leading edge, `1` centres it.
    let contentCentering: CGFloat
    /// Cross-fade weight between the row layout and the card's centred one.
    let cardContentWeight: CGFloat
}
