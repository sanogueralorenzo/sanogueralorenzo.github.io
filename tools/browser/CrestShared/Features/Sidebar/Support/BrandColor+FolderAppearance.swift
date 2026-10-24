import Foundation

extension BrandColor {
    // MARK: - Static Variables

    /// The opacity of the white highlight a folder's artwork lays over its
    /// front face.
    static let folderFrontHighlightOpacity = 0.12

    // MARK: - Variables

    /// The artwork's white highlight composited over its front face, including
    /// translucent custom colors.
    var folderFrontColor: BrandColor {
        let highlight = Self.folderFrontHighlightOpacity
        let baseAlpha = self.alpha * (1 - highlight)
        let alpha = baseAlpha + highlight
        return BrandColor(
            red: (red * baseAlpha + highlight) / alpha,
            green: (green * baseAlpha + highlight) / alpha,
            blue: (blue * baseAlpha + highlight) / alpha,
            alpha: alpha)
    }

    // MARK: - Actions - Folder Appearance

    /// Keep the folder hue while separating its title from the tinted surface.
    func folderTitleColor(onDarkBackground: Bool) -> BrandColor {
        let face = folderFrontColor
        let contrast = onDarkBackground ? 0.27 : 0.32
        let lift = onDarkBackground ? contrast : 0
        return BrandColor(
            red: face.red * (1 - contrast) + lift,
            green: face.green * (1 - contrast) + lift,
            blue: face.blue * (1 - contrast) + lift,
            alpha: face.alpha)
    }

    /// An icon-only symbol follows its tinted title, so the glyph and the words
    /// beside it read as one folder. Emoji keep the colors they ship with.
    func folderSymbolColor(for symbol: String, tintsTitle: Bool, onDarkBackground: Bool) -> BrandColor? {
        guard tintsTitle, BrowserIconSymbol.emoji(from: symbol) == nil else { return nil }
        return folderTitleColor(onDarkBackground: onDarkBackground)
    }

    /// This color at `opacity`, flattened over an opaque `background`.
    func composited(opacity: Double, over background: BrandColor) -> BrandColor {
        let alpha = self.alpha * opacity
        return BrandColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha))
    }
}
