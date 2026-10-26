import SwiftUI

extension Color {
    // MARK: - Actions - Contrast

    /// Black or white, whichever reads better over this background in
    /// `colorScheme`.
    func readableForeground(colorScheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        return readableForeground(environment: environment)
    }

    /// Black or white, whichever reads better over this background as
    /// `environment` resolves it.
    func readableForeground(environment: EnvironmentValues) -> Color {
        let blackRatio = Color.black.contrastRatio(over: self, environment: environment)
        let whiteRatio = Color.white.contrastRatio(over: self, environment: environment)
        return blackRatio >= whiteRatio ? .black : .white
    }

    /// The contrast of this foreground, composited by its own opacity, over
    /// `background` as `environment` resolves both.
    func contrastRatio(over background: Color, environment: EnvironmentValues) -> Double {
        let resolvedForeground = resolve(in: environment)
        let resolvedBackground = background.resolve(in: environment)
        let backgroundLuminance = resolvedBackground.relativeLuminance
        let foregroundLuminance = resolvedForeground.relativeLuminance
        let foregroundOpacity = Double(resolvedForeground.opacity)
        let compositedForegroundLuminance =
            foregroundLuminance * foregroundOpacity
            + backgroundLuminance * (1 - foregroundOpacity)
        return (Swift.max(compositedForegroundLuminance, backgroundLuminance) + 0.05)
            / (Swift.min(compositedForegroundLuminance, backgroundLuminance) + 0.05)
    }
}

extension Color.Resolved {
    // MARK: - Variables

    /// The colour's relative luminance, as WCAG contrast measures it.
    fileprivate var relativeLuminance: Double {
        0.2126 * Double(linearRed)
            + 0.7152 * Double(linearGreen)
            + 0.0722 * Double(linearBlue)
    }
}
