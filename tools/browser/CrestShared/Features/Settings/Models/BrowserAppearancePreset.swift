import Foundation

/// A named stop on a continuous appearance control.
///
/// The presets are the whole control for most readers; the exact value stays
/// available in the group's Fine tune disclosure. A preset reads as selected
/// only while the stored value is close enough to it to be indistinguishable on
/// screen, so dragging the exact slider simply clears the segments.
struct BrowserAppearancePreset: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let value: Double
}

enum BrowserAppearancePresets {
    static let cornerRadiusTolerance = 0.5
    static let tabScaleTolerance = 0.025

    static var cornerRadius: [BrowserAppearancePreset] {
        [
            .init(id: "square", title: String(localized: "Square"), value: 0),
            .init(id: "soft", title: String(localized: "Soft"), value: 6),
            .init(id: "round", title: String(localized: "Round"), value: BrowserLookAndFeelDefaults.cornerRadius),
            .init(id: "capsule", title: String(localized: "Capsule"), value: 40),
        ]
    }

    static var tabScale: [BrowserAppearancePreset] {
        [
            .init(id: "compact", title: String(localized: "Compact"), value: 0.85),
            .init(id: "default", title: String(localized: "Default"), value: BrowserLookAndFeelDefaults.tabScale),
            .init(id: "comfortable", title: String(localized: "Comfortable"), value: 1.15),
        ]
    }

    /// The preset a stored value currently reads as, if any.
    static func match(_ value: Double, in presets: [BrowserAppearancePreset], tolerance: Double)
        -> BrowserAppearancePreset?
    {
        guard value.isFinite else { return nil }
        return presets.first { abs($0.value - value) <= tolerance }
    }
}
