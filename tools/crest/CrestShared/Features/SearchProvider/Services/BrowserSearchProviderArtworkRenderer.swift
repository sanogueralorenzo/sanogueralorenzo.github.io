import SwiftUI

/// The one way Crest draws a search provider's logo or site icon as an image:
/// fitted, at its own proportions, inside a square of exactly the size asked
/// for.
///
/// Native picker and menu cells stretch a resizable image to the width of their
/// label, so a provider's icon has to reach those controls already drawn at its
/// size. Bundled logos are drawn synchronously, when a view or menu asks, and
/// each logo, size, appearance and scale is drawn once and kept.
@MainActor
final class BrowserSearchProviderArtworkRenderer {
    // MARK: - Static Variables

    static let shared = BrowserSearchProviderArtworkRenderer()

    // MARK: - Types

    private struct LogoIdentity: Equatable {
        let logo: String
        let size: CGFloat
        let colorScheme: ColorScheme
        let scale: CGFloat
    }

    private struct Drawing {
        let identity: LogoIdentity
        let image: CGImage
    }

    // MARK: - Variables

    /// The most logo drawings kept, the least recently used going first: every
    /// bundled logo at each size the palette, settings and pickers show.
    private let capacity: Int
    private var drawings: [Drawing] = []

    // MARK: - Initializers

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Actions - Drawing

    /// The bundled logo named `logo`, fitted into a square `size` points wide,
    /// drawn in `colorScheme` at `scale` pixels per point, or nil in the
    /// unlikely case SwiftUI could not draw it.
    func image(logo: String, size: CGFloat, colorScheme: ColorScheme, scale: CGFloat) -> CGImage? {
        let identity = LogoIdentity(logo: logo, size: size, colorScheme: colorScheme, scale: scale)
        if let index = drawings.firstIndex(where: { $0.identity == identity }) {
            let drawing = drawings.remove(at: index)
            drawings.append(drawing)
            return drawing.image
        }
        let content = Image(logo)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
        guard let image = draw(content, size: size, colorScheme: colorScheme, scale: scale) else { return nil }
        if drawings.count == capacity { drawings.removeFirst() }
        drawings.append(Drawing(identity: identity, image: image))
        return image
    }

    /// A site's own icon, fitted into a square `size` points wide with softened
    /// corners and drawn at `scale` pixels per point. The view that fetched the
    /// icon keeps this drawing, so it is drawn once per fetch rather than kept here.
    func image(siteIcon: CGImage, size: CGFloat, scale: CGFloat) -> CGImage? {
        let content = Image(decorative: siteIcon, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(.rect(cornerRadius: size * 0.18))
        return draw(content, size: size, colorScheme: .light, scale: scale)
    }

    private func draw(_ content: some View, size: CGFloat, colorScheme: ColorScheme, scale: CGFloat) -> CGImage? {
        let framed =
            content
            .frame(width: size, height: size)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: framed)
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        renderer.scale = scale
        return renderer.cgImage
    }
}
