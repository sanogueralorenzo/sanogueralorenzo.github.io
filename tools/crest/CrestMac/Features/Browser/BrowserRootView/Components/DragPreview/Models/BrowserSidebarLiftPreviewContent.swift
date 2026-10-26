import CoreGraphics
import Foundation

/// Everything the preview window draws for a lifted sidebar row, as one
/// comparable value.
///
/// The subject travels with the lift because the preview shows the real row —
/// title and favicon, or a folder, or a group's members — and the reorder state
/// carries only identifiers.
struct BrowserSidebarLiftPreviewContent: Equatable {
    // MARK: - Variables

    let subject: BrowserSidebarLiftPreviewSubject
    /// The images the lifted tabs wear.
    let favicons: FaviconAssets
    let lift: BrowserSidebarFloatingLift
    /// Passed in rather than read from the environment: the preview is hosted in
    /// a window of its own, which inherits nothing from the browser's.
    let reduceMotion: Bool
    var selectedTabID: UUID?
    var loadedTabIDs: Set<UUID> = []

    /// A conservative envelope in the source window's top-left coordinates.
    /// Cover both ends of a morph so resizing the native panel cannot clip the
    /// animation, including a selection gathering from its original row offsets.
    var drawingBounds: CGRect {
        let rowSize = BrowserTabDragPreviewLayout.rowSize
        let base = CGSize(
            width: max(
                BrowserTabDragPreviewLayout.resolvedRowWidth(lift.rowWidth), lift.sourceSize.width,
                lift.pinnedTileSize.width, BrowserTabDragPreviewLayout.cardSize.width),
            height: max(
                rowSize.height, lift.sourceSize.height, lift.pinnedTileSize.height,
                BrowserTabDragPreviewLayout.cardSize.height))
        let size = subject.drawingExtent(from: base, of: lift)

        let scale = BrowserSidebarReorderVisuals.liftScale
        let pointer = lift.presentationPointer
        let extent = CGSize(width: size.width * scale + 48, height: size.height * scale + 48)
        var bounds = CGRect(
            x: pointer.x - extent.width, y: pointer.y - extent.height,
            width: extent.width * 2, height: extent.height * 2)
        if let landing = lift.landing {
            bounds = bounds.union(landing.frame.insetBy(dx: -extent.width, dy: -extent.height))
        }
        if lift.constraintMessage != nil {
            // The short constraint label is at most 280 points wide. The
            // existing preview envelope leaves room for its wrapped caption.
            bounds = bounds.union(
                CGRect(
                    x: pointer.x + 12, y: pointer.y + lift.sourceSize.height + 12,
                    width: 280, height: extent.height))
        }
        return bounds
    }
}

extension BrowserSidebarLiftPreviewContent {
    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subject == rhs.subject && lhs.favicons === rhs.favicons && lhs.lift == rhs.lift
            && lhs.reduceMotion == rhs.reduceMotion && lhs.selectedTabID == rhs.selectedTabID
            && lhs.loadedTabIDs == rhs.loadedTabIDs
    }
}
