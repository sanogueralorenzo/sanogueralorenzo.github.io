import SwiftUI

/// Which side of a window's field-to-palette morph holds the shared identity.
///
/// The sidebar's address field stays on screen while the command palette is
/// open, so the two never hold ``BrowserCommandSurfaceMorph/commandPalette(spaceID:)``
/// together: with two sources in one group SwiftUI has no single frame to
/// follow. The field lets go as the palette opens, so the palette's frame grows
/// out of the field's, and takes the identity back as the palette closes, so
/// the palette shrinks back into it.
struct BrowserCommandPaletteHandoff: Equatable, Sendable {
    // MARK: - Static Variables

    /// The field rests on screen holding the identity, so a palette that
    /// opens grows out of it.
    static let field = Self(
        fieldHoldsMorph: true,
        fieldOpacity: 1,
        fieldAnimation: BrowserCommandSurfaceMorph.trailingFade
    )

    /// The open palette holds the identity. The field keeps its place in the
    /// sidebar, faded out, until the palette shrinks back into it.
    static let palette = Self(
        fieldHoldsMorph: false,
        fieldOpacity: 0,
        fieldAnimation: BrowserCommandSurfaceMorph.leadingFade
    )

    /// Neither holds it. The field is off screen or the palette does not
    /// animate, so the palette appears and leaves where it rests and the field
    /// stays put.
    static let neither = Self(
        fieldHoldsMorph: false,
        fieldOpacity: 1,
        fieldAnimation: BrowserCommandSurfaceMorph.trailingFade
    )

    // MARK: - Variables

    /// Whether the field carries the identity right now.
    let fieldHoldsMorph: Bool

    /// How much of the field shows.
    let fieldOpacity: Double

    /// The pace at which the field reaches `fieldOpacity` when the hand-off
    /// arrives at this side.
    let fieldAnimation: Animation

    // MARK: - Initializers

    private init(fieldHoldsMorph: Bool, fieldOpacity: Double, fieldAnimation: Animation) {
        self.fieldHoldsMorph = fieldHoldsMorph
        self.fieldOpacity = fieldOpacity
        self.fieldAnimation = fieldAnimation
    }

    // MARK: - Actions - Resolution

    /// The side holding the identity in a window.
    ///
    /// - Parameters:
    ///   - isPaletteShown: Whether the window shows its overlay palette, not
    ///     merely whether one was asked for: a palette over a Space the reader
    ///     cannot act in never appears, and the field must not fade for it.
    ///   - isFieldOnScreen: Whether the sidebar carrying the field is on
    ///     screen. A collapsed sidebar still lays its field out off the
    ///     window's edge, and a palette must not fly in from there.
    ///   - animates: Whether the palette morphs at all
    ///     (``BrowserCommandSurfaceMorph/animatesCommandPalette(reduceMotion:)``).
    static func resolve(
        isPaletteShown: Bool,
        isFieldOnScreen: Bool,
        animates: Bool
    ) -> Self {
        if !animates { return .neither }
        if isPaletteShown { return .palette }
        return isFieldOnScreen ? .field : .neither
    }
}
