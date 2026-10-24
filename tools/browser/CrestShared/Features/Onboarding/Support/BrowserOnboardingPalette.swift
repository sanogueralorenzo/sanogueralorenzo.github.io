import SwiftUI

/// Scheme-aware roles for the setup and import flow.
///
/// The editorial palette remains the source of Crest's hues, while the setup
/// window uses the same semantic canvas, surface, text, line, and accent roles
/// as the rest of the app so every step follows the system appearance.
enum BrowserOnboardingPalette {
    static let inkComponents = CrestBrandPalette.inkComponents
    static let inkSoftComponents = CrestBrandPalette.inkSoftComponents
    static let paperComponents = CrestBrandPalette.paperComponents
    static let parchmentComponents = CrestBrandPalette.parchmentComponents
    static let butterComponents = CrestBrandPalette.butterComponents
    static let coralComponents = CrestBrandPalette.coralComponents
    static let sageComponents = CrestBrandPalette.sageComponents
    static let skyComponents = CrestBrandPalette.skyComponents

    static let ink = CrestBrandTheme.textDisplay
    static let inkSoft = Color.secondary
    static let paper = CrestBrandTheme.canvas
    static let parchment = CrestBrandTheme.surface
    static let coral = CrestBrandTheme.accent
    static let line = CrestBrandTheme.line

    static let butter = CrestBrandPalette.butter
    static let sage = CrestBrandPalette.sage
    static let sky = CrestBrandPalette.sky
    static let match = sage
}
