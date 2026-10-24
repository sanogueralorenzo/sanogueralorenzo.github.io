import SwiftUI

/// A search provider's icon: its bundled logo, else its site's own icon,
/// fetched from the site in the Space's profile, else its kind's symbol.
///
/// Logos and site icons keep their proportions inside a square of exactly
/// `size` points, already drawn at that size: a native picker or menu cell
/// stretches a resizable image to the width of its label.
struct BrowserSearchProviderIcon: View {
    // MARK: - Types

    /// What the fetched site icon was drawn for: a new provider, profile, size
    /// or screen scale draws it again.
    private struct SiteIconRequest: Equatable {
        let provider: String
        let profileID: UUID?
        let size: CGFloat
        let scale: CGFloat
    }

    /// A fetched site icon as drawn for one request. It shows only while that
    /// request is current, so a drawing for another size or scale never does.
    private struct SiteIcon {
        let request: SiteIconRequest
        let image: CGImage
    }

    // MARK: - Variables

    let provider: SearchProvider
    var profileID: UUID? = nil
    var size: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var siteIcon: SiteIcon?

    var body: some View {
        Group {
            if let artwork {
                Image(decorative: artwork, scale: displayScale)
                    .renderingMode(.original)
                    .interpolation(.high)
            } else {
                Image(systemName: provider.kind.symbol)
                    .font(.system(size: size * 0.65, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: siteIconRequest) {
            await loadSiteIcon(siteIconRequest)
        }
    }

    // MARK: - Actions - Artwork

    private var artwork: CGImage? {
        guard let logo = provider.logo else {
            return siteIcon.flatMap { $0.request == siteIconRequest ? $0.image : nil }
        }
        return BrowserSearchProviderArtworkRenderer.shared.image(
            logo: logo, size: size, colorScheme: colorScheme, scale: displayScale)
    }

    private var siteIconRequest: SiteIconRequest {
        SiteIconRequest(provider: provider.name, profileID: profileID, size: size, scale: displayScale)
    }

    private func loadSiteIcon(_ request: SiteIconRequest) async {
        guard
            provider.logo == nil,
            let profileID = request.profileID,
            let pageURL = provider.iconPageURL
        else {
            siteIcon = nil
            return
        }
        guard
            let data = await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            ),
            let image = await BrowserFaviconImageDecoder.decode(
                data,
                maximumPixelSize: 64
            ),
            !Task.isCancelled
        else { return }
        siteIcon = BrowserSearchProviderArtworkRenderer.shared.image(
            siteIcon: image, size: request.size, scale: request.scale
        )
        .map { SiteIcon(request: request, image: $0) }
    }
}
