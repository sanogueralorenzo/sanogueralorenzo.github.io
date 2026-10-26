import SwiftUI

struct BrowserSpaceSymbolArtworkIdentity: Equatable, Sendable {
    private enum Artwork: Equatable, Sendable {
        case crest(SpaceCrest, colors: ColorPalette)
        case symbol(color: BrandColor)
        case emoji
    }

    private let artwork: Artwork
    let symbol: String
    let requiresAuthentication: Bool
    let size: CGFloat
    let lockSize: CGFloat
    let colorScheme: ColorScheme
    let displayScale: CGFloat

    init(
        branding: SpaceBranding,
        symbol: String,
        requiresAuthentication: Bool,
        size: CGFloat,
        lockSize: CGFloat,
        colorScheme: ColorScheme,
        displayScale: CGFloat
    ) {
        if branding.iconStyle == .layeredCrest {
            var crest = branding.crest
            crest.startingPresetID = nil
            artwork = .crest(crest, colors: crest.layerColors(spaceColors: branding.colors))
        } else if BrowserIconSymbol.emoji(from: symbol) != nil {
            artwork = .emoji
        } else {
            artwork = .symbol(color: branding.resolvedSymbolColor)
        }
        self.symbol = symbol
        self.requiresAuthentication = requiresAuthentication
        self.size = size
        self.lockSize = lockSize
        self.colorScheme = colorScheme
        self.displayScale = displayScale
    }
}
