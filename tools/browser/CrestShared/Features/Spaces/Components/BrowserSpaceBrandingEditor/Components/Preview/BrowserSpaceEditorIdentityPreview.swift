import SwiftUI

struct BrowserSpaceEditorIdentityPreview: View {
    let branding: SpaceBranding
    let symbol: String
    var size: CGFloat = BrowserSpaceForgeMetrics.previewIdentitySize

    var body: some View {
        Group {
            if branding.iconStyle == .layeredCrest {
                BrowserSpaceCrestIcon(
                    branding: branding,
                    size: size
                )
            } else {
                if let emoji = BrowserIconSymbol.emoji(from: symbol) {
                    Text(emoji)
                        .font(.system(size: size * 0.68))
                        .frame(
                            width: size,
                            height: size
                        )
                } else {
                    Image(systemName: symbol)
                        .font(
                            .system(
                                size: size * 0.56,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(branding.primaryColor.color)
                        .frame(
                            width: size,
                            height: size
                        )
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSpaceEditorIdentityPreview(
            branding: BrowserSpaceBrandingPreviewFixture.crestBranding, symbol: "crown.fill"
        ).padding()
    }
#endif
