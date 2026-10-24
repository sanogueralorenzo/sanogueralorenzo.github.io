import CoreGraphics

/// Where an anchored fill prompt lands, and how wide it is when it gets there.
///
/// Kept apart from the view that draws it because the whole of the decision is
/// arithmetic over four rectangles, and because a panel that lands off the page
/// is not something a screenshot review catches reliably.
struct BrowserCredentialPromptPlacement: Equatable, Sendable {
    // MARK: - Variables

    /// The prompt's top-leading corner, in the same space the field was given
    /// in.
    let origin: CGPoint

    /// Whether the prompt ended up above the field rather than below it.
    let isAboveField: Bool

    // MARK: - Initializers

    init(origin: CGPoint, isAboveField: Bool) {
        self.origin = origin
        self.isAboveField = isAboveField
    }

    /// Where a prompt of `size` goes when it is pointing at `field`.
    ///
    /// Below the field and aligned to its leading edge is the answer whenever
    /// there is room. Where there is not, the prompt goes above rather than
    /// hanging off the bottom of the page — and where there is room for
    /// neither, it stays below and is pushed back inside the insets, because a
    /// clipped prompt still beats an invisible one.
    init(
        field: CGRect,
        size: CGSize,
        container: CGSize,
        gap: CGFloat,
        inset: CGFloat
    ) {
        let below = field.maxY + gap
        let above = field.minY - gap - size.height
        let lowestTop = container.height - inset - size.height
        let fitsBelow = below <= lowestTop
        let fitsAbove = above >= inset
        let isAboveField = !fitsBelow && fitsAbove

        self.init(
            origin: CGPoint(
                x: Self.clamp(
                    field.minX,
                    lowerBound: inset,
                    upperBound: container.width - inset - size.width
                ),
                y: Self.clamp(
                    isAboveField ? above : below,
                    lowerBound: inset,
                    upperBound: lowestTop
                )
            ),
            isAboveField: isAboveField
        )
    }

    // MARK: - Actions - Sizing

    /// How wide a prompt anchored under `field` should be.
    ///
    /// A password box is usually wider than it is interesting, and sometimes
    /// narrower than a sentence — so the field proposes and the profile
    /// disposes. The page itself is the last word: a panel is never wider than
    /// the room left between the insets.
    static func width(
        field: CGRect,
        container: CGSize,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
        inset: CGFloat
    ) -> CGFloat {
        let available = container.width - inset * 2
        let bounded = min(max(field.width, minimumWidth), maximumWidth)
        guard available > 0 else { return bounded }
        return min(bounded, available)
    }

    /// Keeps a coordinate inside its bounds, and inside the lower one where the
    /// two have crossed — a page smaller than the prompt it is showing.
    private static func clamp(
        _ value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else { return lowerBound }
        return min(max(value, lowerBound), upperBound)
    }
}
