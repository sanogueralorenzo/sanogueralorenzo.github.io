import SwiftUI

/// The scheme-aware semantic layer over `CrestBrandPalette`.
///
/// `CrestBrandPalette` holds the fixed paper-and-ink identity used by the
/// website and by light-only editorial surfaces. `CrestBrandTheme` names the
/// *roles* those hues play and flips each role between light and dark, so
/// Crest-authored chrome can adopt the brand without hardcoding an appearance.
///
/// Dark variants keep the light hue and lift luminance only as far as legibility
/// demands: paper and ink simply trade places, and coral is lifted (hue held at
/// roughly 8°, saturation held near 0.84) so it stays readable on ink without
/// reading as a different colour. Every pair below clears WCAG AA for text
/// (4.5:1) or non-text (3:1) in both schemes; `CrestDesignLanguageTests` pins the
/// measured ratios.
enum CrestBrandTheme {
    // MARK: - Component pairs

    /// Coral, lifted for dark: same hue family as `CrestBrandPalette.coral`, with
    /// enough luminance to sit on ink.
    static let accentLightComponents = CrestBrandPalette.coralComponents
    static let accentDarkComponents = CrestColorComponents(red: 241, green: 117, blue: 98)

    /// The accent when it is *text* rather than a tint.
    ///
    /// `accent` is scoped to the 3:1 non-text minimum, which is all a fill, a stroke,
    /// or a glyph needs. A text-only control — `CrestButtonStyle`'s `.tertiary` and
    /// `.destructive` roles — is text, and has to clear 4.5:1 against both `canvas`
    /// and `surface`. Coral cannot do that in light, so this role holds it at the same
    /// hue (roughly 8°) and saturation family while trading value for legibility:
    /// darker on paper, lifted on ink.
    static let accentTextLightComponents = CrestColorComponents(red: 178, green: 64, blue: 47)
    static let accentTextDarkComponents = CrestColorComponents(red: 250, green: 120, blue: 101)

    static let canvasLightComponents = CrestBrandPalette.paperComponents
    static let canvasDarkComponents = CrestBrandPalette.inkComponents

    static let surfaceLightComponents = CrestBrandPalette.parchmentComponents
    static let surfaceDarkComponents = CrestBrandPalette.inkSoftComponents

    static let textDisplayLightComponents = CrestBrandPalette.inkComponents
    static let textDisplayDarkComponents = CrestBrandPalette.paperComponents

    static let lineLightComponents = CrestBrandPalette.inkComponents
    static let lineDarkComponents = CrestBrandPalette.paperComponents
    /// Matches `CrestBrandPalette.line`; the dark hairline is lifted because paper
    /// on ink loses definition faster than ink on paper.
    static let lineLightOpacity = 0.18
    static let lineDarkOpacity = 0.22

    // MARK: - Semantic roles

    /// Brand accent for interactive emphasis and tint.
    static let accent = dynamic(light: accentLightComponents, dark: accentDarkComponents)
    /// Brand accent for text-weight controls. See `accentTextLightComponents`.
    static let accentText = dynamic(
        light: accentTextLightComponents,
        dark: accentTextDarkComponents
    )
    /// The page the content sits on.
    static let canvas = dynamic(light: canvasLightComponents, dark: canvasDarkComponents)
    /// A raised card or panel on the canvas.
    static let surface = dynamic(light: surfaceLightComponents, dark: surfaceDarkComponents)
    /// Display and body text on `canvas` or `surface`.
    static let textDisplay = dynamic(
        light: textDisplayLightComponents,
        dark: textDisplayDarkComponents
    )
    /// Hairline separators and control borders.
    static let line = dynamic(
        light: lineLightComponents,
        lightOpacity: lineLightOpacity,
        dark: lineDarkComponents,
        darkOpacity: lineDarkOpacity
    )

    // MARK: - Scheme-resolved colors

    /// The role values as flat colors, for tests and for surfaces that already
    /// know which appearance they render in.
    static func accent(_ colorScheme: ColorScheme) -> Color {
        components(accentLightComponents, accentDarkComponents, colorScheme).color
    }

    static func accentText(_ colorScheme: ColorScheme) -> Color {
        components(accentTextLightComponents, accentTextDarkComponents, colorScheme).color
    }

    static func canvas(_ colorScheme: ColorScheme) -> Color {
        components(canvasLightComponents, canvasDarkComponents, colorScheme).color
    }

    static func surface(_ colorScheme: ColorScheme) -> Color {
        components(surfaceLightComponents, surfaceDarkComponents, colorScheme).color
    }

    static func textDisplay(_ colorScheme: ColorScheme) -> Color {
        components(textDisplayLightComponents, textDisplayDarkComponents, colorScheme).color
    }

    static func line(_ colorScheme: ColorScheme) -> Color {
        let base = components(lineLightComponents, lineDarkComponents, colorScheme)
        return base.color.opacity(colorScheme == .dark ? lineDarkOpacity : lineLightOpacity)
    }

    private static func components(
        _ light: CrestColorComponents,
        _ dark: CrestColorComponents,
        _ colorScheme: ColorScheme
    ) -> CrestColorComponents {
        colorScheme == .dark ? dark : light
    }

    // MARK: - Dynamic construction

    private static func dynamic(
        light: CrestColorComponents,
        lightOpacity: Double = 1,
        dark: CrestColorComponents,
        darkOpacity: Double = 1
    ) -> Color {
        CrestPlatformDynamicColor.make(
            light: light,
            lightOpacity: lightOpacity,
            dark: dark,
            darkOpacity: darkOpacity
        )
    }
}
