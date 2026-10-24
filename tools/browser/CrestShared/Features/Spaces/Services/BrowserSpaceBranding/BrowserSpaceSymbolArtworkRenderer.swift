import SwiftUI

/// The one way Crest draws a Space's icon as an image: its crest, or its
/// symbol when it wears no crest, with the lock of a Space that asks for
/// authentication, as the Space switcher draws it.
///
/// It draws synchronously, when a view or menu asks, so the icon a menu
/// captures is the Space's own the first time the menu opens, never a stand-in
/// shown while a render is under way. Each look, size, appearance and scale is
/// drawn once and kept, so a changed look is simply a new drawing.
@MainActor
final class BrowserSpaceSymbolArtworkRenderer {
    // MARK: - Static Variables

    static let shared = BrowserSpaceSymbolArtworkRenderer()

    // MARK: - Types

    private struct Drawing {
        let identity: BrowserSpaceSymbolArtworkIdentity
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

    /// The icon of `space`, `size` points square with a lock `lockSize` points
    /// tall, drawn in `colorScheme` at `scale` pixels per point, or nil in the
    /// unlikely case SwiftUI could not draw it.
    func image(
        for space: BrowserSpaceIdentity, size: CGFloat, lockSize: CGFloat, colorScheme: ColorScheme, scale: CGFloat
    ) -> CGImage? {
        let identity = BrowserSpaceSymbolArtworkIdentity(
            branding: space.branding, symbol: space.symbol, requiresAuthentication: space.requiresAuthentication,
            size: size, lockSize: lockSize, colorScheme: colorScheme, displayScale: scale)
        if let index = drawings.firstIndex(where: { $0.identity == identity }) {
            let drawing = drawings.remove(at: index)
            drawings.append(drawing)
            return drawing.image
        }
        let renderer = ImageRenderer(
            content: BrowserSpaceSymbolArtworkContent(identity: space, size: size, lockSize: lockSize)
                .environment(\.colorScheme, colorScheme))
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        if drawings.count == capacity { drawings.removeFirst() }
        drawings.append(Drawing(identity: identity, image: image))
        return image
    }
}
