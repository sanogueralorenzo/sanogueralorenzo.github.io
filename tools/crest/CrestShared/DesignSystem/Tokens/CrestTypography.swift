import SwiftUI

/// Dynamic Type-aware roles for Crest-authored content.
///
/// Crest pairs a serif display face with a humanist sans for body and controls.
/// Both faces ship with macOS and iOS, so nothing is embedded in the bundle.
enum CrestTypography {
    /// The serif display face used for brand voice: hero lines, page titles, and
    /// section headings in Crest-authored surfaces.
    static let displayFontName = "Iowan Old Style"
    /// The humanist sans used for supporting copy and control labels.
    static let sansFontName = "Avenir Next"

    static let controlTitle = Font.body.weight(.medium)
    static let metadata = Font.caption
    static let compactMetadata = Font.caption2
    static let badge = Font.caption2.monospaced().weight(.semibold)

    /// Display serif that scales with Dynamic Type against `style`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(displayFontName, size: size, relativeTo: style)
    }

    /// Display serif at a fixed optical size. Retained for hand-tuned editorial
    /// layouts (the onboarding wizard) whose line breaks are composed by hand.
    static func display(_ size: CGFloat) -> Font {
        .custom(displayFontName, size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(sansFontName, size: size).weight(weight)
    }

    // MARK: - Named display roles

    /// Title of a single page or pane inside a Crest-authored flow.
    static let displayPageSize: CGFloat = 24
    /// Heading that opens a group of rows inside a pane.
    static let displaySectionSize: CGFloat = 17

    static var displayPage: Font { display(displayPageSize, relativeTo: .title2) }
    static var displaySection: Font { display(displaySectionSize, relativeTo: .title3) }
}
