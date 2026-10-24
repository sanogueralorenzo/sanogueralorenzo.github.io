import CoreGraphics

enum BrowserCommandPaletteLayout {
    static let maximumResultAreaHeight = BrowserCommandPaletteMetrics.maximumResultAreaHeight

    /// The height the results take: each group's rows, with a header above
    /// a group that has one, the spacing between groups and the padding
    /// around them, at most `maximumHeight`.
    static func resultAreaHeight(
        groups: [(hasHeader: Bool, rows: Int)],
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        let shown = groups.filter { $0.rows > 0 }
        guard !shown.isEmpty else { return 0 }
        let groupsHeight = shown.reduce(CGFloat.zero) { total, group in
            total
                + (group.hasHeader
                    ? BrowserCommandPaletteMetrics.resultHeaderHeight + BrowserCommandPaletteMetrics.resultRowSpacing
                    : 0)
                + CGFloat(group.rows) * BrowserCommandPaletteMetrics.resultRowHeight
                + CGFloat(group.rows - 1) * BrowserCommandPaletteMetrics.resultRowSpacing
        }
        let spacing = CGFloat(shown.count - 1) * BrowserCommandPaletteMetrics.resultSectionSpacing
        return min(BrowserCommandPaletteMetrics.resultOuterPadding + groupsHeight + spacing, max(0, maximumHeight))
    }

    static func resultAreaHeight(
        tabCount: Int,
        includesPrimaryAction: Bool,
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        resultAreaHeight(
            groups: [(false, includesPrimaryAction ? 1 : 0), (true, max(0, tabCount))],
            maximumHeight: maximumHeight
        )
    }

    /// The overlay card's width in the space its layer leaves it: as wide as
    /// the palette allows, less the padding around the card.
    static func overlayCardWidth(availableWidth: CGFloat) -> CGFloat {
        min(
            BrowserCommandPaletteMetrics.maximumCardWidth,
            max(0, availableWidth - BrowserCommandPaletteMetrics.overlayCardPadding * 2)
        )
    }

    /// How far below the top of the space its layer leaves it the overlay
    /// card's top edge rests: where a card with its tallest results would sit
    /// centered, so the top never moves as results come and go and the card
    /// only grows downward, as on iPhone and iPad.
    static func overlayTopInset(availableHeight: CGFloat) -> CGFloat {
        let tallestCard =
            BrowserCommandPaletteMetrics.searchFieldMinimumHeight
            + overlayResultAreaHeight(availableHeight: availableHeight)
        return max(BrowserCommandPaletteMetrics.overlayCardPadding, (availableHeight - tallestCard) / 2)
    }

    static func overlayResultAreaHeight(availableHeight: CGFloat) -> CGFloat {
        max(
            BrowserCommandPaletteMetrics.minimumOverlayResultHeight,
            min(
                maximumResultAreaHeight,
                availableHeight - BrowserCommandPaletteMetrics.overlayReservedHeight
            )
        )
    }

}
