import Foundation

/// The text tone a palette reads best under, measured as the banner renders
/// it: each color composited at the banner's strength over the opposite base,
/// beneath the readability fade.
extension ColorPalette {
    // MARK: - Actions - Contrast

    /// The tone that reads best over this palette drawn at `strength`, under
    /// a readability fade of `readabilityFade`.
    func foregroundTone(
        strength: Double,
        readabilityFade: Double
    ) -> BrowserSpaceForegroundTone {
        let lightContrast = minimumContrast(
            for: .light,
            strength: strength,
            readabilityFade: readabilityFade
        )
        let darkContrast = minimumContrast(
            for: .dark,
            strength: strength,
            readabilityFade: readabilityFade
        )
        return lightContrast >= darkContrast ? .light : .dark
    }

    private func minimumContrast(
        for tone: BrowserSpaceForegroundTone,
        strength: Double,
        readabilityFade: Double
    ) -> Double {
        let baseChannel = tone == .light ? 0.0 : 1.0
        let textLuminance = tone == .light ? 1.0 : 0.0
        let readabilityOverlay = Swift.min(readabilityFade * 0.55, 0.7)

        return map { color in
            let red = Self.renderedChannel(
                color.red,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let green = Self.renderedChannel(
                color.green,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let blue = Self.renderedChannel(
                color.blue,
                base: baseChannel,
                strength: strength,
                overlay: readabilityOverlay
            )
            let backgroundLuminance =
                0.2126 * Self.linearComponent(red)
                + 0.7152 * Self.linearComponent(green)
                + 0.0722 * Self.linearComponent(blue)
            let lighter = Swift.max(textLuminance, backgroundLuminance)
            let darker = Swift.min(textLuminance, backgroundLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }
        .min() ?? 1
    }

    private static func renderedChannel(
        _ channel: Double,
        base: Double,
        strength: Double,
        overlay: Double
    ) -> Double {
        let composited = channel * strength + base * (1 - strength)
        return composited * (1 - overlay)
    }

    private static func linearComponent(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}
