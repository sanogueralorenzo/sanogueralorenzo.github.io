import Foundation

/// A crest's composition as the Studio edits and the renderer draws it: the
/// colors and figure the layers use.
extension SpaceCrest {
    // MARK: - Static Variables

    /// The most colors a crest's own palette holds, as the core enforces it.
    static var maximumPaletteCount: Int { CapacityLimits.current.crestPalette }

    // MARK: - Variables

    /// The figure this crest draws: a custom charge when one was chosen, else
    /// the heraldic symbol.
    var resolvedCharge: CrestCharge {
        charge ?? .heraldic(symbol)
    }

    /// Whether the crest draws with its own tinctures rather than the Space's.
    var usesOwnPalette: Bool { palette != nil }

    // MARK: - Actions - Colors

    /// The colors this crest's layer indices point into.
    func layerColors(spaceColors: ColorPalette) -> ColorPalette {
        if let palette, !palette.isEmpty { return palette }
        return spaceColors.isEmpty ? [.indigo] : spaceColors
    }
}

extension CrestMeasure {
    /// The range the renderer draws the measure in.
    var range: ClosedRange<Double> { minimum...maximum }

    /// The range of a count, in whole pieces.
    var countRange: ClosedRange<Int> { Int(minimum)...Int(maximum) }
}
