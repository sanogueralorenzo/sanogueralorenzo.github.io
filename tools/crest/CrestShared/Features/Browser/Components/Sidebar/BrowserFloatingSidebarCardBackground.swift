import SwiftUI

struct BrowserFloatingSidebarCardBackground: View {
    private static let spaceThemeOpacity = 1.0

    let space: SpaceModel?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            platformBackground

            if let space {
                BrowserSpaceBannerBackground(branding: space.settings.look.shown)
                    .opacity(Self.spaceThemeOpacity)
            }

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        .white.opacity(
                            BrowserRootMetrics.floatingSidebarHighlightOpacity
                        ),
                        .clear,
                        .black.opacity(
                            BrowserRootMetrics.floatingSidebarShadeOpacity
                        ),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// The Mac grounds the card in the window's own color; touch layers it on
    /// the secondary system background.
    private var platformBackground: Color {
        #if os(macOS)
            CrestColor.windowBackground
        #else
            Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
