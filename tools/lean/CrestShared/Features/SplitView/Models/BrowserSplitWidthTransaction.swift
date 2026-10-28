import CoreGraphics

/// Keeps divider updates local until the interaction commits.
struct BrowserSplitWidthTransaction: Equatable {
    private(set) var fractions: [Double]
    private(set) var persistedFractions: [Double]

    /// Total drag translation is measured from these fractions, never the previous frame.
    private var dragBaseline: [Double]?

    /// Ignores subpixel fraction changes when deciding whether to persist.
    private static let minimumMeaningfulChange = 0.0005

    init(persistedFractions: [Double]) {
        let fractions = BrowserSplitColumnLayout.normalizedFractions(persistedFractions)
        self.fractions = fractions
        self.persistedFractions = fractions
    }

    /// Replacing split membership cancels the drag and adopts its saved layout.
    mutating func begin(fractions: [Double]) {
        let normalized = BrowserSplitColumnLayout.normalizedFractions(fractions)
        self.fractions = normalized
        persistedFractions = normalized
        dragBaseline = nil
    }

    /// Applies total drag travel to the baseline captured on the first update.
    mutating func resize(dividerIndex: Int, delta: CGFloat, containerWidth: CGFloat) {
        let baseline = dragBaseline ?? fractions
        dragBaseline = baseline
        fractions = BrowserSplitColumnLayout.fractionsAfterResize(
            fractions: baseline,
            dividerIndex: dividerIndex,
            delta: delta,
            containerWidth: containerWidth
        )
    }

    /// Returns changed fractions once per completed interaction.
    mutating func commit() -> [Double]? {
        dragBaseline = nil
        guard !Self.matches(fractions, persistedFractions) else { return nil }
        persistedFractions = fractions
        return fractions
    }

    private static func matches(_ fractions: [Double], _ other: [Double]) -> Bool {
        guard fractions.count == other.count else { return false }
        return zip(fractions, other).allSatisfy { pair in
            abs(pair.0 - pair.1) < minimumMeaningfulChange
        }
    }
}
