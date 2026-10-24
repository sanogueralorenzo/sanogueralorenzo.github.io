import SwiftUI

struct BrowserSpaceThemeField: View {
    let themeMode: SpaceThemeMode
    let bannerPattern: SpaceBannerPattern
    let gradientAngle: Double
    let colors: [Color]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        switch themeMode.kind {
        case .banner:
            BrowserSpaceBannerField(
                pattern: bannerPattern,
                colors: colors,
                size: size
            )
        case .gradient:
            BrowserSpaceGradientField(
                colors: colors,
                angle: gradientAngle
            )
        }
    }
}
