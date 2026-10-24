import SwiftUI

/// A matched-geometry identity in a window's command-surface namespace: one
/// Space's sidebar address field, paired with a surface it turns into.
///
/// A window keeps one namespace for all of its Spaces, so every identity names
/// its Space. Switching Spaces with the command palette open never morphs the
/// palette into another Space's field.
///
/// The type also owns the pacing of the field-to-palette hand-off, so the
/// field, the palette's surface, and the palette's contents share one timeline.
struct BrowserCommandSurfaceMorph: Hashable, Sendable {
    // MARK: - Static Variables

    /// The palette's frame and corner radius, both ways: the smooth hand-off
    /// the sidebar makes between its docked and floating placements.
    static let animation = CrestMotion.sidebarMorph

    /// A fade that runs as the frame starts to move: the field letting go and
    /// the palette's glass taking over on open, the palette's contents
    /// clearing on close.
    static let leadingFade = CrestMotion.contentReveal

    /// A fade that finishes as the frame settles: the palette's contents on
    /// open, the palette's glass and the field trading places on close.
    static let trailingFade = CrestMotion.contentReveal.delay(
        CrestMotion.sidebarMorphTransition - CrestMotion.contentRevealTransition
    )

    // MARK: - Types

    /// The surface a Space's address field turns into.
    enum Counterpart: Hashable, Sendable {
        /// The command palette. It grows out of the field, which keeps its
        /// place in the sidebar faded out, and shrinks back into it.
        case commandPalette
        /// The utility search toolbar, which takes the field's place while
        /// History or Downloads shows.
        case utilitySearch
    }

    // MARK: - Variables

    let spaceID: UUID
    let counterpart: Counterpart

    // MARK: - Initializers

    static func commandPalette(spaceID: UUID) -> Self {
        Self(spaceID: spaceID, counterpart: .commandPalette)
    }

    static func utilitySearch(spaceID: UUID) -> Self {
        Self(spaceID: spaceID, counterpart: .utilitySearch)
    }

    // MARK: - Actions - Command palette

    /// Whether the command palette grows out of its Space's address field and
    /// shrinks back into it. Reduce Motion turns the morph off, and so does
    /// the reader in Look and Feel; either way the palette opens and closes
    /// in place at once.
    @MainActor
    static func animatesCommandPalette(reduceMotion: Bool) -> Bool {
        !reduceMotion && BrowserDeviceAppearanceStore.shared.address.animatesIntoCommandPalette
    }

    /// The pace of the palette's arrival and departure, or nil when it
    /// opens and closes at once.
    @MainActor
    static func commandPaletteAnimation(reduceMotion: Bool) -> Animation? {
        animatesCommandPalette(reduceMotion: reduceMotion) ? animation : nil
    }
}
