import CoreGraphics

/// The whole of Crest's column arithmetic: fractions in, widths out.
///
/// Every function here is pure and deterministic, which is what lets one set of
/// numbers serve the macOS layout manager, the iPad columns, and the unit tests
/// without a view in the loop. Two invariants hold across all of them:
///
/// - Widths are never negative.
/// - Widths sum to the container's available width — the container minus the
///   gaps between columns — whenever the container can hold the columns'
///   minimums. When it cannot, every card falls back to its minimum and the
///   container clips. Layout never dissolves a split to make it fit.
///
/// Fractions are shares of that available width and always sum to one.
enum BrowserSplitColumnLayout {
    /// The fractions of a split nobody has resized yet: equal columns.
    static func equalFractions(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return Array(repeating: 1 / Double(count), count: count)
    }

    /// The slot a tab dragged over the content area would take among
    /// `orderedCardFrames`, in `0...orderedCardFrames.count`. Pure geometry,
    /// so a drop can be exercised without a live drag.
    ///
    /// The columns view lays cards out in reading order along one axis, so the
    /// rule is the horizontal twin of `BrowserSidebarReorderRow.insertionIndex`:
    /// the pointer has passed a card once it is beyond that card's midpoint,
    /// and the index is how many cards it has passed.
    ///
    /// Only presented cards are measured. The drop placeholder registers no
    /// frame of its own, and the cards it displaces provably keep the same
    /// answer: inserting a placeholder at `index` moves every earlier card's
    /// midpoint left and every later card's midpoint right, which is the
    /// direction that reinforces the index the pointer already resolved. That
    /// is what lets the placeholder appear without the layout it causes
    /// changing the slot it appears in.
    ///
    /// A lone card is not a special case: the pointer resolves to `0` on its
    /// leading half and `1` on its trailing half, which is exactly how a split
    /// gets created out of a window presenting one tab.
    static func insertionIndex(
        at point: CGPoint,
        orderedCardFrames: [CGRect]
    ) -> Int {
        var index = 0
        for frame in orderedCardFrames {
            guard point.x > frame.midX else { break }
            index += 1
        }
        return index
    }

    /// Reading order for measured cards.
    ///
    /// Sorting by leading edge rather than trusting a dictionary's iteration is
    /// what keeps the index tied to what is on screen. It matches the ordering
    /// `BrowserSidebarReorderRow` already uses for the pinned grid, including
    /// its indifference to layout direction.
    static func orderedCardFrames(_ frames: [CGRect]) -> [CGRect] {
        frames.filter { !$0.isEmpty }.sorted { $0.minX < $1.minX }
    }

    /// Which fractions a split starts a layout pass with.
    ///
    /// Two callers need the same answer and must not disagree: the window
    /// model, seeding its width transaction when the presented group changes,
    /// and the columns view, which lays out every frame and cannot index a
    /// fraction list that is one member behind the group it is drawing. A
    /// stored list whose length no longer matches the group is not repaired
    /// here — a split of three has no honest reading of two fractions — so it
    /// is discarded for equal columns, the same starting point a brand-new
    /// group gets.
    static func seedFractions(persisted: [Double]?, memberCount: Int) -> [Double] {
        guard memberCount > 0 else { return [] }
        guard let persisted, persisted.count == memberCount else {
            return equalFractions(count: memberCount)
        }
        return normalizedFractions(persisted)
    }

    /// The caller's fractions as shares summing to one.
    ///
    /// A list containing anything that cannot be a share — a non-finite value,
    /// zero, a negative — falls back to equal columns in full rather than
    /// salvaging the readable entries. Partially trusting a malformed list
    /// produces layouts nobody asked for; equal columns are at least the
    /// documented starting point.
    static func normalizedFractions(_ fractions: [Double]) -> [Double] {
        guard !fractions.isEmpty else { return [] }
        guard fractions.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return equalFractions(count: fractions.count)
        }
        let total = fractions.reduce(0, +)
        guard total.isFinite, total > 0 else {
            return equalFractions(count: fractions.count)
        }
        return fractions.map { $0 / total }
    }

    /// The width of each card in a container of this width.
    ///
    /// Fractions are normalized, distributed across the width left after the
    /// gaps, floored at `minimum`, and the overflow that flooring creates is
    /// taken back from the cards still above the floor in proportion to their
    /// shares. A container that cannot seat every card at `minimum` returns
    /// minimums and clips.
    static func widths(
        containerWidth: CGFloat,
        fractions: [Double],
        gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap,
        minimum: CGFloat = BrowserSplitLayoutMetrics.minimumCardWidth
    ) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }
        let floorWidth = max(0, minimum)
        let available = availableWidth(
            containerWidth: containerWidth,
            columnCount: fractions.count,
            gap: gap
        )
        guard available > floorWidth * CGFloat(fractions.count) else {
            return Array(repeating: floorWidth, count: fractions.count)
        }

        let shares = normalizedFractions(fractions)
        var widths = [CGFloat](repeating: 0, count: fractions.count)
        var flexible = Array(widths.indices)
        var remaining = available

        // `available` exceeds every card's floor combined, so each pass leaves
        // at least one card above the floor and the loop always terminates.
        while !flexible.isEmpty {
            let shareTotal = flexible.reduce(0.0) { $0 + shares[$1] }
            guard shareTotal > 0 else {
                let equalWidth = remaining / CGFloat(flexible.count)
                for index in flexible {
                    widths[index] = equalWidth
                }
                break
            }
            for index in flexible {
                widths[index] = remaining * CGFloat(shares[index] / shareTotal)
            }
            let flooring = flexible.filter { widths[$0] < floorWidth }
            guard !flooring.isEmpty else { break }
            for index in flooring {
                widths[index] = floorWidth
                remaining -= floorWidth
            }
            flexible.removeAll(where: flooring.contains)
        }

        return distributingResidual(widths, across: available)
    }

    /// The fractions a divider drag lands on.
    ///
    /// `dividerIndex` names the gap after that card, `delta` is the pointer's
    /// travel from where the drag began, and only the pair around the divider
    /// moves: the cards beyond it keep the widths they had, which is what makes
    /// a drag feel local. The pair's own boundary stops as soon as either side
    /// reaches `minimum`, and a pair with no room to give returns unchanged
    /// fractions.
    static func fractionsAfterResize(
        fractions: [Double],
        dividerIndex: Int,
        delta: CGFloat,
        containerWidth: CGFloat,
        gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap,
        minimum: CGFloat = BrowserSplitLayoutMetrics.minimumCardWidth
    ) -> [Double] {
        var shares = normalizedFractions(fractions)
        guard shares.count > 1, dividerIndex >= 0, dividerIndex < shares.count - 1 else {
            return shares
        }
        let available = availableWidth(
            containerWidth: containerWidth,
            columnCount: shares.count,
            gap: gap
        )
        guard available > 0 else { return shares }

        let floorWidth = max(0, minimum)
        let pairWidth = available * CGFloat(shares[dividerIndex] + shares[dividerIndex + 1])
        guard pairWidth >= floorWidth * 2 else { return shares }

        let leadingWidth = available * CGFloat(shares[dividerIndex])
        let resolvedWidth = min(max(leadingWidth + delta, floorWidth), pairWidth - floorWidth)
        shares[dividerIndex] = Double(resolvedWidth / available)
        shares[dividerIndex + 1] = Double((pairWidth - resolvedWidth) / available)
        return shares
    }

    /// How far one divider's handle sits from the row's leading edge, which
    /// centers its hit width on the gap after `dividerIndex`.
    ///
    /// Pure, and deliberately so: the handle's position is a function of the
    /// widths the drag is writing, which is exactly why a drag can never be
    /// measured against the handle's own frame. `BrowserSplitResizeSpace` is
    /// where it is measured instead, and the test that pairs the two is what
    /// keeps the boundary tracking the pointer one to one.
    static func dividerLeadingDistance(
        after dividerIndex: Int,
        cardWidths: [CGFloat],
        gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap,
        handleWidth: CGFloat = BrowserSplitLayoutMetrics.resizeHandleHitWidth
    ) -> CGFloat {
        guard dividerIndex >= 0 else { return 0 }
        let cards = cardWidths.prefix(dividerIndex + 1).reduce(0, +)
        let gapCenter = cards + gap * CGFloat(dividerIndex) + gap / 2
        return gapCenter - handleWidth / 2
    }

    /// The fractions after a card joins at `index`.
    ///
    /// The newcomer takes an equal share of the wider split it creates and the
    /// existing cards give it up in proportion, so a resized pair stays as
    /// lopsided as its owner left it.
    ///
    /// A drag in flight lays its drop placeholder out with these same fractions.
    /// The placeholder is not a hint about where a card would go, it is that
    /// card's own column drawn a moment early — half the row beside a lone card,
    /// a third among two, a quarter among three — so the slot under the pointer
    /// is already the width the card that lands in it will have.
    static func fractionsInserting(at index: Int, into fractions: [Double]) -> [Double] {
        guard !fractions.isEmpty else { return [1] }
        let shares = normalizedFractions(fractions)
        let newcomerShare = 1 / Double(shares.count + 1)
        var result = shares.map { $0 * (1 - newcomerShare) }
        result.insert(newcomerShare, at: min(max(index, 0), result.count))
        return result
    }

    /// The width columns share once the gaps between them are paid for.
    private static func availableWidth(
        containerWidth: CGFloat,
        columnCount: Int,
        gap: CGFloat
    ) -> CGFloat {
        guard columnCount > 1 else { return containerWidth }
        return containerWidth - max(0, gap) * CGFloat(columnCount - 1)
    }

    /// Absorbs division noise into the widest card so the widths sum to the
    /// available width exactly. The widest card is by definition further above
    /// the floor than the correction, so flooring survives.
    private static func distributingResidual(
        _ widths: [CGFloat],
        across total: CGFloat
    ) -> [CGFloat] {
        var widths = widths
        let residual = total - widths.reduce(0, +)
        guard residual != 0,
            let widest = widths.indices.max(by: { widths[$0] < widths[$1] })
        else { return widths }
        widths[widest] += residual
        return widths
    }
}
