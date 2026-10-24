import SwiftUI

/// The trailing control's drawn geometry, resolved once per shell rather than
/// spelled out by each row.
///
/// `controlSize` is the frame the button claims — the hit target — and
/// `glyphSize` the point size of the symbol inside it. The two are separate
/// because a touch target grows well past the glyph it contains.
struct BrowserTabTrailingControlMetrics: Equatable, Sendable {
    let controlSize: CGSize
    let glyphSize: CGFloat
    let glyphWeight: Font.Weight

    /// Whether the control stays on screen regardless of hover and selection.
    let isAlwaysVisible: Bool

    /// The opacity a visible close control rests at on a row that is not
    /// selected.
    ///
    /// A shell that hides the control until it is asked for has already made
    /// the control deliberate by the time it is drawn, so it draws at full
    /// strength. A shell that cannot hide it has an xmark on every row at all
    /// times instead, and holding the unselected ones back is what keeps the
    /// list reading as titles rather than as a column of close buttons.
    let restingCloseOpacity: CGFloat

    /// Whether the control wears the chrome's hover-and-press treatment.
    ///
    /// That treatment is a response to a pointer resting on the control, which
    /// is exactly what a touch shell has no way to show; there the button is
    /// drawn plain and the press is the system's own.
    let usesChromeControlStyle: Bool

    /// A pointer shell: the chrome control size, a light glyph, and a control
    /// that waits for hover or selection before it appears.
    ///
    /// The target stays tied to `CrestLayout.minimumHitTarget` rather than to a
    /// number, because every other pointer control in the chrome is sized from
    /// that token and the row has no reason to be the one that drifts.
    static let pointer = BrowserTabTrailingControlMetrics(
        controlSize: CGSize(
            width: CrestLayout.minimumHitTarget,
            height: CrestLayout.minimumHitTarget
        ),
        glyphSize: 12,
        glyphWeight: .regular,
        isAlwaysVisible: false,
        restingCloseOpacity: 1,
        usesChromeControlStyle: true
    )

    /// A touch shell: a full 44pt target and a heavier glyph to read at that
    /// size, always drawn because nothing can reveal it.
    static let touch = BrowserTabTrailingControlMetrics(
        controlSize: CGSize(width: 44, height: 44),
        glyphSize: 14,
        glyphWeight: .medium,
        isAlwaysVisible: true,
        restingCloseOpacity: 0.65,
        usesChromeControlStyle: false
    )

    /// Whether the control is drawn at all, given what the row can tell the
    /// reader about itself right now.
    ///
    /// Selection counts alongside hover because the selected row is the one a
    /// reader is most likely to want to close, and it is the one row a pointer
    /// shell can reveal the control on without a pointer being there.
    func isRevealed(isHovering: Bool, isSelected: Bool) -> Bool {
        isAlwaysVisible || isHovering || isSelected
    }

    /// The opacity a revealed close control draws at.
    func closeOpacity(isSelected: Bool) -> CGFloat {
        isSelected ? 1 : restingCloseOpacity
    }
}
