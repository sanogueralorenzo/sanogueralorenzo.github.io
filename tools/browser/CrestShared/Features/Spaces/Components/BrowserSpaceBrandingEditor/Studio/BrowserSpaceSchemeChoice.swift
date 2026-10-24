import SwiftUI

/// A scheme in a starting-point gallery: the Space's own icon as the scheme
/// draws it, on the scheme's sidebar; choosing it gives the Space that sidebar.
struct BrowserSpaceSchemeChoice: View {
    let scheme: SpaceScheme
    @Binding var branding: SpaceBranding
    let symbol: String
    var size: CGFloat = BrowserCrestForgeMetrics.tileCrestSize
    var tint: Color = CrestBrandTheme.accent

    var body: some View {
        BrowserCrestStudioChoice(title: scheme.title, selected: scheme.isWorn(by: branding), tint: tint) {
            branding = scheme.applying(to: branding)
        } artwork: {
            BrowserCrestStudioMark(branding: scheme.applying(to: branding), symbol: symbol, size: size * 0.55)
                .frame(width: size, height: size)
                .background { BrowserSpaceBannerBackground(branding: scheme.look) }
                .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
        }
    }
}
