import CoreGraphics

enum BrowserTabDragPreviewLayout {
    static let rowSize = CGSize(width: 220, height: 40)
    static let pinnedSize = CGSize(width: 52, height: 52)
    /// A page-shaped drop preview: wide enough to read as a web page at a
    /// glance, small enough to leave the cards it is about to join visible
    /// underneath it.
    static let cardSize = CGSize(width: 240, height: 160)
    static let sourceHorizontalInsets = CrestSpacing.small * 2
    static let defaultRowWidth =
        BrowserChromeLayout.sidebarIdealWidth
        - sourceHorizontalInsets
    static let maximumRowWidth =
        BrowserChromeLayout.sidebarMaximumWidth
        - sourceHorizontalInsets

    static func rowWidth(forSourceWidth sourceWidth: CGFloat) -> CGFloat {
        guard sourceWidth.isFinite,
            sourceWidth >= BrowserChromeLayout.sidebarMinimumWidth,
            sourceWidth <= BrowserChromeLayout.sidebarMaximumWidth
        else {
            return defaultRowWidth
        }
        return resolvedRowWidth(sourceWidth - sourceHorizontalInsets)
    }

    static func resolvedRowWidth(_ proposedWidth: CGFloat) -> CGFloat {
        min(max(proposedWidth, rowSize.width), maximumRowWidth)
    }

    /// The preview part-way between two shapes.
    ///
    /// Every number is a straight interpolation of the same number on either
    /// shape, so adding a shape adds no arithmetic here and no pair is more
    /// special than another.
    static func metrics(
        from source: BrowserTabDragPreviewShape,
        to destination: BrowserTabDragPreviewShape,
        progress proposedProgress: CGFloat,
        rowWidth: CGFloat = rowSize.width,
        pinnedSize: CGSize = BrowserTabDragPreviewLayout.pinnedSize
    ) -> BrowserTabDragPreviewMetrics {
        let progress = min(max(proposedProgress, 0), 1)
        let sourceSize = source.size(rowWidth: rowWidth, pinnedSize: pinnedSize)
        let destinationSize = destination.size(rowWidth: rowWidth, pinnedSize: pinnedSize)
        return BrowserTabDragPreviewMetrics(
            width: lerp(sourceSize.width, destinationSize.width, progress),
            height: lerp(sourceSize.height, destinationSize.height, progress),
            titleOpacity: Double(
                lerp(
                    CGFloat(source.titleOpacity),
                    CGFloat(destination.titleOpacity),
                    progress
                )
            ),
            contentCentering: lerp(
                source.contentCentering,
                destination.contentCentering,
                progress
            ),
            cardContentWeight: lerp(
                source.cardContentWeight,
                destination.cardContentWeight,
                progress
            )
        )
    }

    /// The preview's corner part-way between two shapes, where a row and a
    /// pinned tile wear `layerCornerRadius`.
    static func cornerRadius(
        from source: BrowserTabDragPreviewShape,
        to destination: BrowserTabDragPreviewShape,
        progress proposedProgress: CGFloat,
        layerCornerRadius: CGFloat
    ) -> CGFloat {
        lerp(
            source.cornerRadius(layerCornerRadius: layerCornerRadius),
            destination.cornerRadius(layerCornerRadius: layerCornerRadius),
            min(max(proposedProgress, 0), 1)
        )
    }

    /// The row-to-pinned-tile morph, which is what a preview shows unless a
    /// caller names another destination. Kept as its own entry point so the
    /// oldest and most-seen morph in the app is expressed exactly as it always
    /// was, and so the mobile previews that only know a placement keep working.
    static func metrics(
        progress: CGFloat,
        rowWidth: CGFloat = rowSize.width
    ) -> BrowserTabDragPreviewMetrics {
        metrics(
            from: .row,
            to: .pinnedTile,
            progress: progress,
            rowWidth: rowWidth
        )
    }

    static func progress(for placement: TabPlacement) -> CGFloat {
        placement.isGrid ? 1 : 0
    }

    /// The fraction of the preview held by the pointer, along one axis.
    ///
    /// It starts as wherever the row was grabbed and drifts to the middle as the
    /// new shape forms, so a shrinking preview shrinks around the cursor instead
    /// of sliding out from under it.
    static func anchorFraction(
        grabbed: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let clamped = min(max(grabbed, 0), 1)
        return clamped + ((0.5 - clamped) * min(max(progress, 0), 1))
    }

    private static func lerp(
        _ start: CGFloat,
        _ end: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}
