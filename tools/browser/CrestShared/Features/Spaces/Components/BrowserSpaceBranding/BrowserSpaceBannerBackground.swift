import SwiftUI

struct BrowserSpaceBannerBackground: View {
    let branding: SpaceBranding

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let previewReduceTransparency: Bool?
    private let previewContrast: ColorSchemeContrast?

    init(branding: SpaceBranding) {
        self.branding = branding
        previewReduceTransparency = nil
        previewContrast = nil
    }

    init(
        previewBranding branding: SpaceBranding,
        reduceTransparency: Bool,
        contrast: ColorSchemeContrast
    ) {
        self.branding = branding
        previewReduceTransparency = reduceTransparency
        previewContrast = contrast
    }

    var body: some View {
        GeometryReader { geometry in
            let colors = resolvedColors
            ZStack {
                BrowserPlatformSpaceBrandingStyle.backgroundColor
                BrowserSpaceThemeField(
                    themeMode: branding.themeMode,
                    bannerPattern: branding.bannerPattern,
                    gradientAngle: branding.gradientAngle,
                    colors: colors,
                    size: geometry.size
                )
                .opacity(fieldOpacity)

                if readabilityOpacity > 0 {
                    Color.black.opacity(readabilityOpacity)
                }

                if branding.themeMode == .gradient, branding.showsTexture {
                    BrowserSpaceThemeTexture()
                        .blendMode(.softLight)
                        .opacity(effectiveReduceTransparency ? 0.24 : 0.38)
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var resolvedColors: [Color] {
        let colors = branding.colors.map(\.color)
        return colors.isEmpty ? [BrandColor.indigo.color] : colors
    }

    private var fieldOpacity: Double {
        effectiveReduceTransparency
            ? max(branding.bannerStrength, 0.85) : branding.bannerStrength
    }

    private var readabilityOpacity: Double {
        let configured =
            effectiveReduceTransparency
            ? max(branding.readabilityFade, 0.42)
            : branding.readabilityFade
        let increasedContrast = effectiveContrast == .increased ? 0.1 : 0
        return min(configured * 0.55 + increasedContrast, 0.7)
    }

    private var effectiveReduceTransparency: Bool {
        previewReduceTransparency ?? reduceTransparency
    }

    private var effectiveContrast: ColorSchemeContrast {
        previewContrast ?? contrast
    }
}

#if DEBUG
    #Preview("Banner and gradient") {
        HStack(spacing: 16) {
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.bannerBranding)
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.gradientBranding)
        }.frame(width: 500, height: 360).padding()
    }
#endif
