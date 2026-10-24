import SwiftUI

struct BrowserWindowAtmosphere: View {
    // MARK: - Variables

    /// The Space the window shows, or nil for none.
    let space: SpaceModel?

    /// The Space's look as the current appearance shows it, read in `body`
    /// so it follows the appearance and Space-colors preferences.
    private var branding: SpaceBranding? {
        space.map(\.settings.look.shown)
    }

    private var platformBackground: Color {
        BrowserPlatformWindowAtmosphereStyle.backgroundColor
    }

    var body: some View {
        ZStack {
            platformBackground
            if let branding {
                BrowserSpaceBannerBackground(branding: branding)
            }
        }
        .accessibilityHidden(true)
    }
}
