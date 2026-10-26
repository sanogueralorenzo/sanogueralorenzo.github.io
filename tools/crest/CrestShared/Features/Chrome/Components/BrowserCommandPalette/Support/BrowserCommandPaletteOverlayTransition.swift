import SwiftUI

extension EnvironmentValues {
    /// Where the overlay command palette is in its arrival or departure.
    /// Anything outside an overlay transition reads it as settled.
    @Entry var browserCommandPaletteTransitionPhase = TransitionPhase.identity
}

/// The overlay palette's arrival and departure.
///
/// It animates nothing itself. It hands its phase to the palette, whose scrim
/// fades with the frame and whose card fades its glass and its contents on
/// their own paces, so the glass can take over from the address field before
/// the contents appear on it.
struct BrowserCommandPaletteOverlayTransition: Transition {
    // MARK: - Static Variables

    /// The phase moves nothing on its own. A card that grows out of the
    /// address field is moved by its matched geometry, which Reduce Motion
    /// and the Look and Feel choice already turn off.
    static let properties = TransitionProperties(hasMotion: false)

    // MARK: - Actions - Transition

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.environment(\.browserCommandPaletteTransitionPhase, phase)
    }
}

extension Transition where Self == BrowserCommandPaletteOverlayTransition {
    static var browserCommandPaletteOverlay: Self { Self() }
}
