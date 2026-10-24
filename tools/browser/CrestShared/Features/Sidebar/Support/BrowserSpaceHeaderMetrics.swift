import SwiftUI

/// The drawn geometry of a Space header, resolved once per shell rather than
/// spelled out by each header.
///
/// The header is one row of chrome that both shells draw, and everything they
/// used to disagree about was a size: how big the identity icon is, how big
/// the chevron standing in for it is, and how much room the actions menu
/// claims. None of that is a platform fact — it follows from the least precise
/// input the shell accepts, the same way the tab row's geometry does.
struct BrowserSpaceHeaderMetrics: Equatable, Sendable {
    /// The most a fixed-height header's content may grow to, or nil for no cap.
    private static let fixedContentMaxHeight: CGFloat? = nil

    /// The point size of the chevron that replaces the identity icon while the
    /// saved tabs are collapsed.
    let disclosureGlyphSize: CGFloat

    /// The square the identity icon — or the chevron standing in for it — is
    /// drawn into.
    let iconSize: CGFloat

    /// The square the actions menu's ellipsis claims.
    let actionsControlSize: CGFloat

    /// The point size the ellipsis is drawn at, where the shell sizes it
    /// itself. A pointer shell leaves it to the ambient font, which is already
    /// sized for a control read from a foot away.
    let actionsGlyph: BrowserSpaceHeaderActionsGlyph?

    /// Whether the header is a fixed band the title fills.
    ///
    /// A pointer shell pins the row to one exact height so the sidebar stays a
    /// scannable column. A touch shell lets the row grow with its label —
    /// pinning the title to an unbounded height there would fight that — and
    /// holds only a floor.
    let fillsRowHeight: Bool

    /// Whether the actions menu claims its whole frame as a hit target.
    ///
    /// A finger has to be able to land anywhere in the 44pt square, so the
    /// square itself is the target. A pointer aims at the glyph and lets the
    /// menu's own chrome decide the rest.
    let expandsActionsHitArea: Bool

    /// A pointer shell: a small icon, a small ellipsis at the ambient size, and
    /// a row held to one exact height.
    static let pointer = BrowserSpaceHeaderMetrics(
        disclosureGlyphSize: 9,
        iconSize: 20,
        actionsControlSize: 24,
        actionsGlyph: nil,
        fillsRowHeight: true,
        expandsActionsHitArea: false
    )

    /// A touch shell: a larger icon, a full 44pt menu target with a glyph sized
    /// to read at that scale, and a row that grows with its label.
    static let touch = BrowserSpaceHeaderMetrics(
        disclosureGlyphSize: 10,
        iconSize: 22,
        actionsControlSize: 44,
        actionsGlyph: BrowserSpaceHeaderActionsGlyph(size: 17, weight: .medium),
        fillsRowHeight: false,
        expandsActionsHitArea: true
    )

    /// The ceiling the title area is held to, which is what keeps the pinned
    /// header at its intrinsic height where the row is not a fixed band.
    var contentMaxHeight: CGFloat? {
        fillsRowHeight
            ? .infinity
            : Self.fixedContentMaxHeight
    }
}

/// The ellipsis a shell draws its Space actions menu with, where it sizes the
/// symbol rather than inheriting it.
struct BrowserSpaceHeaderActionsGlyph: Equatable, Sendable {
    let size: CGFloat
    let weight: Font.Weight

    var font: Font {
        .system(size: size, weight: weight)
    }
}
