import SwiftUI

/// An engine's mark beside its name in the Opens in menu, or an empty slot the
/// same size for an engine without one, so every name starts at the same edge.
///
/// A native menu flattens its items to images and text, so the mark arrives
/// already drawn, in its own colours, for the menu's appearance and scale.
struct BrowserSiteEngineMenuIcon: View {
    // MARK: - Static Variables

    /// The slot every engine's icon fills, the width of a menu's symbols.
    private static let side: CGFloat = 16

    /// The mark inside that slot, inset like a symbol's glyph.
    private static let markSize: CGFloat = 14

    /// Every drawing made so far, kept for good. The menu knows an image by
    /// its identity, so a drawing freed and drawn again can show as the one
    /// that last held its place, such as WebKit's mark beside Chromium. There
    /// are only a few: one per mark, appearance and scale.
    private static var drawings: [Drawing: Image] = [:]

    // MARK: - Types

    /// One drawing of a mark, or of the empty slot.
    private struct Drawing: Hashable {
        let mark: EngineMark?
        let colorScheme: ColorScheme
        let scale: CGFloat
    }

    // MARK: - Variables

    let mark: EngineMark?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = image(of: Drawing(mark: mark, colorScheme: colorScheme, scale: displayScale)) {
            image.renderingMode(.original)
        }
    }

    // MARK: - Actions - Drawing

    private func image(of drawing: Drawing) -> Image? {
        if let image = Self.drawings[drawing] { return image }
        let renderer = ImageRenderer(content: Self.artwork(of: drawing))
        renderer.scale = drawing.scale
        guard let image = renderer.cgImage.map({ Image(decorative: $0, scale: drawing.scale) }) else { return nil }
        Self.drawings[drawing] = image
        return image
    }

    private static func artwork(of drawing: Drawing) -> some View {
        ZStack {
            if let mark = drawing.mark {
                mark.artwork.frame(width: markSize, height: markSize)
            }
        }
        .frame(width: side, height: side)
        .environment(\.colorScheme, drawing.colorScheme)
    }
}

#if DEBUG
    #Preview("Component") {
        VStack(alignment: .leading) {
            ForEach(EngineKind.all, id: \.self) { engine in
                Label {
                    Text(engine.title)
                } icon: {
                    BrowserSiteEngineMenuIcon(mark: engine.mark)
                }
            }
        }
        .padding()
    }
#endif
