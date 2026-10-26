import SwiftUI

/// Each supported search engine uses its bundled logo.
struct BrowserSearchProviderIcon: View {
    // MARK: - Variables

    let provider: SearchProvider
    var size: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let artwork = BrowserSearchProviderArtworkRenderer.shared.image(
                logo: provider.logo, size: size, colorScheme: colorScheme, scale: displayScale)
            {
                Image(decorative: artwork, scale: displayScale)
                    .renderingMode(.original)
                    .interpolation(.high)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
