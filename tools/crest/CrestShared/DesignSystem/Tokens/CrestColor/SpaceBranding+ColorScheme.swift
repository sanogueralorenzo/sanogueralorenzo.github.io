import SwiftUI

/// A Space's look as a window draws it: as chosen in light, and in dark with
/// its colors dimmed as far as the device asks, under text and controls in
/// the scheme that reads over them in the window's appearance.
extension SpaceBranding {
    // MARK: - Variables

    /// This look as the windows' appearance shows it now.
    @MainActor
    var shown: SpaceBranding {
        let appearance = BrowserDeviceAppearanceStore.shared
        // Light, or dark undimmed, draws the look as chosen, so only a dimmed
        // dark window follows how far the dimming goes.
        guard appearance.dimsSpaceColors else { return self }
        return appearing(in: .dark, dimming: appearance.darkSpaceDimming)
    }

    /// The text color mode this look draws with now. A view that needs only
    /// this tracks whether the windows dim Space colors, not how far.
    @MainActor
    var shownTextColorMode: SpaceTextColorMode {
        BrowserDeviceAppearanceStore.shared.dimsSpaceColors ? .automatic : textColorMode
    }

    // MARK: - Actions - Appearance

    /// This look drawn in `colorScheme`. Dark dims each color `dimming` of the
    /// way, from 0 to 1, toward a charcoal tint of its hue, eases the
    /// readability fade out as it does, and works its text tone out from the
    /// dimmed colors, so a text color chosen for the bright look never draws
    /// dark on dark. Light, or no dimming, draws the look as chosen.
    func appearing(in colorScheme: ColorScheme, dimming: Double) -> SpaceBranding {
        guard colorScheme == .dark, dimming > 0 else { return self }
        var look = self
        look.colors = ColorPalette(colors: colors.map { $0.dimmed(by: dimming) })
        look.readabilityFade = readabilityFade * (1 - dimming)
        look.textColorMode = .automatic
        return look
    }

    // MARK: - Actions - Text

    /// The tone the Space's text reads in over a window in `appearance`.
    func foregroundTone(over appearance: ColorScheme) -> BrowserSpaceForegroundTone {
        foregroundTone(system: BrowserSpaceForegroundTone(readingIn: appearance))
    }

    /// The scheme the Space's sidebar draws in over a window in `appearance`.
    func colorScheme(over appearance: ColorScheme) -> ColorScheme {
        foregroundTone(over: appearance).colorScheme
    }
}
