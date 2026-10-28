import SwiftUI

@MainActor
final class BrowserSpaceArtworkRenderer {
    // MARK: - Static Variables

    static let shared = BrowserSpaceArtworkRenderer()

    // MARK: - Types

    private struct ArtworkIdentity: Equatable {
        let color: SpaceColor
        let size: CGFloat
        let displayScale: CGFloat
    }

    private struct Drawing {
        let identity: ArtworkIdentity
        let image: CGImage
    }

    // MARK: - Variables

    /// The most drawings kept, the least recently used going first: enough for
    /// every Space at each size the switcher, the sidebar and the menus show.
    private let capacity: Int
    private var drawings: [Drawing] = []

    // MARK: - Initializers

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Actions - Drawing

    func image(
        for space: BrowserSpaceIdentity, size: CGFloat, scale: CGFloat
    ) -> CGImage? {
        let identity = ArtworkIdentity(
            color: space.color,
            size: size, displayScale: scale)
        if let index = drawings.firstIndex(where: { $0.identity == identity }) {
            let drawing = drawings.remove(at: index)
            drawings.append(drawing)
            return drawing.image
        }
        let renderer = ImageRenderer(
            content: BrowserSpaceIdentityIcon(identity: space, size: size))
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        if drawings.count == capacity { drawings.removeFirst() }
        drawings.append(Drawing(identity: identity, image: image))
        return image
    }
}
