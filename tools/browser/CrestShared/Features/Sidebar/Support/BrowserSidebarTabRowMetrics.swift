import SwiftUI

/// The drawn geometry of a sidebar tab row, resolved once per shell rather
/// than spelled out by each row.
///
/// Everything here is the row's own layout: how far its content sits from the
/// surface's edges, how much room the favicon column claims, and whether the
/// activation area stretches to the row's full height. The trailing control's
/// own geometry stays in `BrowserTabTrailingControlMetrics`, which the same
/// policy resolves from the same capabilities. Where the surface itself sits,
/// and how round it is, is the sidebar's to say for every layer alike: see
/// `BrowserSidebarMetrics`.
struct BrowserSidebarTabRowMetrics: Equatable, Sendable {
    /// The gap between the activation area and the trailing control.
    let contentSpacing: CGFloat

    /// The inset between the surface's leading edge and the favicon.
    ///
    /// It belongs to the activation area rather than to the row, so the strip
    /// a reader aims at when they mean "open this tab" reaches the edge of the
    /// surface instead of stopping short of it.
    let contentLeadingInset: CGFloat

    /// The inset between the trailing control and the surface's trailing edge.
    let contentTrailingInset: CGFloat

    /// The fixed column the favicon is drawn into, where the shell reserves
    /// one. A touch row sizes its glyph for the distance it is read from and
    /// needs a column wide enough that titles still line up; a pointer row
    /// lets the favicon's own 18pt box do that work.
    let faviconSlot: BrowserSidebarTabFaviconSlot?

    /// Whether the activation area stretches to the row's full height.
    ///
    /// A pointer row is a fixed band, so filling it is what makes the whole
    /// band clickable. A touch row grows with its label instead, and pinning
    /// the activation area to an unbounded height would fight that.
    let fillsRowHeight: Bool

    /// A pointer shell: content tight against its surface, no favicon column,
    /// and an activation area that fills the row's fixed height.
    static let pointer = BrowserSidebarTabRowMetrics(
        contentSpacing: 0,
        contentLeadingInset: 9,
        contentTrailingInset: (CrestLayout.sidebarRowHeight
            - BrowserTabTrailingControlMetrics.pointer.controlSize.height) / 2,
        faviconSlot: nil,
        fillsRowHeight: true
    )

    /// A touch shell: a wider leading inset, a reserved favicon column, and an
    /// activation area that takes the height its label asks for.
    static let touch = BrowserSidebarTabRowMetrics(
        contentSpacing: 4,
        contentLeadingInset: 12,
        contentTrailingInset: 4,
        faviconSlot: BrowserSidebarTabFaviconSlot(
            width: 20,
            glyphSize: 17,
            glyphWeight: .medium
        ),
        fillsRowHeight: false
    )
}

/// The column a row reserves for its favicon.
///
/// `width` is the slot the icon is centered in, and the glyph values size the
/// symbol a tab falls back to when it has no icon of its own — that symbol
/// takes the ambient font otherwise, which is sized for body text rather than
/// for an icon read at arm's length.
struct BrowserSidebarTabFaviconSlot: Equatable, Sendable {
    let width: CGFloat
    let glyphSize: CGFloat
    let glyphWeight: Font.Weight
}
