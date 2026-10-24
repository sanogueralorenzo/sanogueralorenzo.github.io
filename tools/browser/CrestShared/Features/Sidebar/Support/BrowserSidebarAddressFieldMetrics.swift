import SwiftUI

/// The drawn geometry of the sidebar's address field, resolved once per shell
/// rather than spelled out by each fork of the field.
///
/// Everything here is a consequence of the least precise input the shell
/// accepts. A pointer shell holds the field to one exact band and draws the
/// glyphs at reading size; a touch shell gives the same field a finger-sized
/// floor, a wider gutter, and glyphs that still read at arm's length. What the
/// field *contains* is not described here — the accessories are the platform's
/// own and arrive as slots.
struct BrowserSidebarAddressFieldMetrics: Equatable, Sendable {
    /// The gap between the leading glyph, the editor, the clear control, and
    /// the trailing accessory.
    let contentSpacing: CGFloat

    /// The inset between the field's surface and its content.
    let horizontalPadding: CGFloat

    /// The band the field occupies, read together with `growsWithContent`.
    let height: CGFloat

    /// Whether `height` is a floor the field may grow past rather than an exact
    /// height.
    ///
    /// A pointer shell pins the field so the chrome above the tab list stays
    /// one unchanging strip. A touch shell cannot: its field is already a hit
    /// target, and at an accessibility text size the address inside it has to
    /// be allowed to push the band taller rather than clip.
    let growsWithContent: Bool

    /// The ring drawn around the field while it is being edited, at full
    /// strength. The field fades the whole color to nothing when editing ends,
    /// so a shell that wants a softer ring bakes that into the color here.
    let editingRingColor: Color

    let editingRingWidth: CGFloat

    /// The lock or magnifying glass shown where no site control has claimed the
    /// leading slot.
    let leadingGlyphFont: Font

    /// The square the leading glyph is centered in, or `nil` where it sits on
    /// its own intrinsic size.
    ///
    /// A pointer shell reserves the same square its site control would occupy,
    /// so the address does not shift sideways as the two swap. A touch shell
    /// has no site control to swap with and lets the glyph size itself.
    let leadingGlyphSlot: CGFloat?

    /// The clear control's own font, or `nil` to inherit the field's.
    ///
    /// The control is present on both shells under the same rule — the field is
    /// being edited and there is something to clear — but only a touch shell
    /// has to enlarge it, because only there is it aimed at with a finger.
    let clearControlFont: Font?

    /// The square a pointer shell's site security control claims: the same
    /// hit target as a row's trailing control.
    static let securityControlSize = BrowserTabTrailingControlMetrics.pointer.controlSize.height

    /// A pointer shell: one exact 36pt band with the glyph column reserved.
    static let pointer = BrowserSidebarAddressFieldMetrics(
        contentSpacing: 7,
        horizontalPadding: 9,
        height: BrowserChromeLayout.addressHeight,
        growsWithContent: false,
        editingRingColor: CrestColor.selectedBorder,
        editingRingWidth: BrowserChromeLayout.addressEditingRingWidth,
        leadingGlyphFont: .caption.weight(.medium),
        leadingGlyphSlot: securityControlSize,
        clearControlFont: nil
    )

    /// A touch shell: a full 44pt floor, a wider gutter, and controls sized for
    /// a finger.
    ///
    /// The floor is a literal rather than `CrestLayout.sidebarRowHeight`, for
    /// the same reason the touch trailing control is: this profile is compared
    /// against from a suite hosted on macOS, where that token resolves to the
    /// pointer shell's height, and the touch field still has to be 44.
    static let touch = BrowserSidebarAddressFieldMetrics(
        contentSpacing: 8,
        horizontalPadding: 12,
        height: 44,
        growsWithContent: true,
        editingRingColor: Color.accentColor.opacity(0.7),
        editingRingWidth: 1,
        leadingGlyphFont: .system(size: 13, weight: .medium),
        leadingGlyphSlot: nil,
        clearControlFont: .system(size: 15, weight: .medium)
    )
}
