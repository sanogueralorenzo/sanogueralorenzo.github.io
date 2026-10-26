import Foundation

/// Artwork resources and explicit shuffle actions shared by every studio presentation.
enum BrowserCrestStudioAppearance {
    static func shuffle(_ branding: SpaceBranding) -> SpaceBranding {
        var value = branding
        value.iconStyle = .layeredCrest
        value.crest.backplate = [.shield, .frenchShield, .circle, .hexagon, .banner].randomElement() ?? .shield
        value.crest.fieldDivision = [.plain, .perPale, .perBend, .quarterly].randomElement() ?? .plain
        value.crest.ordinary =
            value.crest.fieldDivision == .plain ? [.none, .chevron, .fess, .pale].randomElement() ?? .none : .none
        value.crest.symbol = CrestSymbol.selectable.randomElement() ?? .dragon
        value.crest.charge = nil
        value.crest.chargeLayout = .single
        value.crest.chargeScale = 1.15
        value.crest.chargeOffset = 0
        value.crest.plateScale = 1
        value.crest.trim = [.none, .line, .doubleLine].randomElement() ?? .none
        value.crest.trimWeight = 0.75
        value.crest.edgeWidth = 0
        value.crest.finish = .flat
        value.crest.backplateColorIndex = 0
        value.crest.secondaryFieldColorIndex = min(1, value.crest.layerColors(spaceColors: value.colors).count - 1)
        value.crest.symbolColorIndex = value.crest.layerColors(spaceColors: value.colors).count - 1
        value.crest.trimColorIndex = value.crest.symbolColorIndex
        value.hasCustomAppearance = true
        return value.normalized()
    }

    static let credits: String = {
        guard let url = Bundle.main.url(forResource: "HeraldicArtworkCredits", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "Game-icons.net · CC BY 3.0" }
        return text
    }()
}
