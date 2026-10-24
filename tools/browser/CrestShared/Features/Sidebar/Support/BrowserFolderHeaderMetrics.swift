import SwiftUI

/// The drawn geometry of a saved folder's header row, resolved once per shell
/// rather than spelled out by the header itself.
///
/// The leading inset is deliberately absent: it is not the header's to choose.
/// It comes from `BrowserFolderLayout`, which reads the tab row profile
/// the same capabilities resolve, so the folder symbol and the favicons beneath
/// it share one column.
struct BrowserFolderHeaderMetrics: Equatable, Sendable {
    /// The column the folder symbol is centered in.
    let iconWidth: CGFloat

    /// The point size the folder symbol is drawn at, where the shell sizes it
    /// for the distance the row is read from. `nil` leaves the symbol at the
    /// ambient font, which is what a pointer shell reads it at.
    let iconGlyphSize: CGFloat?

    let iconGlyphWeight: Font.Weight

    /// The inset between the header's content and its trailing edge.
    let contentTrailingInset: CGFloat

    /// Whether the header is a band of one exact height.
    ///
    /// A pointer shell holds every row to the same height so the list stays a
    /// scannable column. A touch shell lets the header grow with its title
    /// instead, for the same reason its tab rows do.
    let usesFixedRowHeight: Bool

    /// A pointer shell: the symbol at the ambient text size in an 18pt column,
    /// content tight against the trailing edge, one fixed row height.
    static let pointer = BrowserFolderHeaderMetrics(
        iconWidth: 18,
        iconGlyphSize: nil,
        iconGlyphWeight: .regular,
        contentTrailingInset: 9,
        usesFixedRowHeight: true
    )

    /// A touch shell: a wider column carrying a symbol sized to be read at
    /// arm's length, room at the trailing edge for the reader's own thumb, and
    /// a row that grows with its title.
    static let touch = BrowserFolderHeaderMetrics(
        iconWidth: 20,
        iconGlyphSize: 17,
        iconGlyphWeight: .medium,
        contentTrailingInset: 18,
        usesFixedRowHeight: false
    )
}
