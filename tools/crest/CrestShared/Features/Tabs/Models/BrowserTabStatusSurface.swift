import SwiftUI

// MARK: - Types

/// The tab a status surface dresses: the accent its row or tile draws in, the
/// corner radius of its shape, and how strongly bars across it show.
struct BrowserTabStatusSurfaceStyle {
    let accent: Color
    let cornerRadius: CGFloat
    let barOpacity: Double
}

/// How a status dresses the whole tab while it lasts, beyond its badge: an
/// outline in the status's own tint, bars across the tab that follow its
/// sound, or both. The row or tile draws it over its fill and under its content, in its
/// own shape.
struct BrowserTabStatusSurface: Sendable {
    // MARK: - Static Variables

    /// The tab's outline in the status's tint, at the weight a pinned tab's
    /// accent border has.
    static let outline = Self(outlineWidth: CrestLayout.pinnedAccentBorderWidth)

    /// Bars across the tab, in the site's own color, that follow the sound
    /// its page plays where the engine measures it and move on their own where
    /// it does not.
    static let equalizer = Self(drawsEqualizer: true)

    // MARK: - Variables

    /// The weight of the outline the surface draws around the tab, or nil for
    /// none.
    let outlineWidth: CGFloat?

    /// Whether the surface fills the tab with bars that follow its sound.
    let drawsEqualizer: Bool

    // MARK: - Initializers

    private init(outlineWidth: CGFloat? = nil, drawsEqualizer: Bool = false) {
        self.outlineWidth = outlineWidth
        self.drawsEqualizer = drawsEqualizer
    }
}
