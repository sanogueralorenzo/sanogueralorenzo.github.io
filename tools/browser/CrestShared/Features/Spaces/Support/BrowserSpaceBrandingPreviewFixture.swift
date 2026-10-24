import Foundation

enum BrowserSpaceBrandingPreviewFixture {
    /// The Winter house look, drawn with its simple symbol.
    static let bannerBranding: SpaceBranding = {
        var look = SpaceHouse.winter.look
        look.iconStyle = .simpleSymbol
        return look
    }()

    /// The Storm house look as a textured gradient, drawn with its simple symbol.
    static let gradientBranding: SpaceBranding = {
        var look = SpaceHouse.storm.look
        look.bannerStrength = 0.82
        look.readabilityFade = 0.2
        look.themeMode = .gradient
        look.gradientAngle = 127
        look.showsTexture = true
        look.iconStyle = .simpleSymbol
        return look
    }()

    /// The Lion house look quartered, under a crowned crest.
    static let crestBranding: SpaceBranding = {
        var look = SpaceHouse.lion.look
        look.bannerPattern = .quartered
        look.crest.backplate = .shield
        look.crest.fieldDivision = .quarterly
        look.crest.ordinary = .bend
        look.crest.trim = .laurel
        look.crest.symbol = .crown
        look.crest.chargeLayout = .trio
        (look.crest.backplateColorIndex, look.crest.secondaryFieldColorIndex) = (1, 0)
        (look.crest.ordinaryColorIndex, look.crest.trimColorIndex) = (2, 2)
        (look.crest.symbolColorIndex, look.crest.edgeColorIndex) = (2, 2)
        (look.crest.trimWeight, look.crest.chargeScale) = (1, 1)
        return look
    }()

    /// A Space wearing the banner look, as the core resolves it.
    @MainActor static let simpleSpace = makeSpace(
        idByte: 0x11,
        profileByte: 0x21,
        name: "Winter",
        symbol: "snowflake",
        accent: .indigo,
        branding: bannerBranding,
        accessPolicy: .open
    )

    /// A guarded Space wearing the layered crest, as the core resolves it.
    @MainActor static let crestSpace = makeSpace(
        idByte: 0x12,
        profileByte: 0x22,
        name: "Lion",
        symbol: "crown.fill",
        accent: .orange,
        branding: crestBranding,
        accessPolicy: .deviceOwnerAuthentication
    )

    @MainActor
    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent,
        branding: SpaceBranding,
        accessPolicy: SpaceAccessPolicy
    ) -> SpaceModel {
        SpaceModel.detached(
            SpaceState.Seed(
                id: deterministicUUID(finalByte: idByte), profileID: deterministicUUID(finalByte: profileByte),
                name: name, symbol: symbol, accent: accent, branding: branding, tabs: [],
                accessPolicy: accessPolicy))
    }

    private static func deterministicUUID(finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x50, 0x41,
                0x43, 0x45,
                0x42, 0x52, 0x41, 0x4E, 0x44, finalByte
            ))
    }
}
