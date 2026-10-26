import Foundation

/// A house as the starting point of a Space's look.
extension SpaceHouse {
    /// The house a crest started from, by the name it recorded. Earlier builds
    /// recorded the house's English title, which differs only in case.
    static func startingPoint(of branding: SpaceBranding) -> SpaceHouse? {
        guard let recorded = branding.crest.startingPresetID else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(recorded) == .orderedSame }
    }

    /// `branding` starting over from the house's look, keeping the Space's
    /// own strengths, folder and text choices. A look that started from a
    /// scheme wore the scheme's strength, fade, texture, text and icon color
    /// rather than the person's, so it takes the house's own instead.
    func applying(to branding: SpaceBranding) -> SpaceBranding {
        var updated = branding
        if SpaceScheme.startingPoint(of: branding) != nil {
            updated.bannerStrength = look.bannerStrength
            updated.readabilityFade = look.readabilityFade
            updated.showsTexture = look.showsTexture
            updated.textColorMode = look.textColorMode
            updated.symbolColor = look.symbolColor
        }
        updated.colors = look.colors
        updated.themeMode = look.themeMode
        updated.bannerPattern = look.bannerPattern
        updated.gradientAngle = look.gradientAngle
        updated.iconStyle = .layeredCrest
        updated.crest = look.crest
        updated.crest.startingPresetID = name
        updated.hasCustomAppearance = false
        return updated.normalized()
    }

    /// Whether `branding` still wears the house's look unchanged.
    func isWorn(by branding: SpaceBranding) -> Bool {
        var crest = branding.crest
        crest.startingPresetID = nil
        return branding.hasCustomAppearance != true && branding.iconStyle == .layeredCrest
            && branding.colors == look.colors && branding.themeMode == look.themeMode
            && (look.themeMode == .gradient || branding.bannerPattern == look.bannerPattern) && crest == look.crest
    }

    /// The colors the house is made of, darkest first.
    var tinctures: [BrandColor] {
        var seen: [BrandColor] = []
        for color in Array(look.colors) + Array(look.crest.palette ?? [])
        where !seen.contains(where: { $0.matches(color) }) {
            seen.append(color)
        }
        return seen.sorted { $0.luminance < $1.luminance }
    }
}
