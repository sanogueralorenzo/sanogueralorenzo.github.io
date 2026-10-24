import SwiftUI

/// A single original-color platform image used anywhere SwiftUI bridges a Space
/// icon into a native control. Without this boundary, menus and pickers can
/// flatten a layered crest into one template symbol or interpret its layers as
/// separate control elements.
///
/// The image is drawn as the view is, never after it: a menu captures its
/// labels once, when it opens, so an icon drawn later would never reach it.
struct BrowserSpaceSymbolArtwork: View {
    // MARK: - Variables

    let identity: BrowserSpaceIdentity
    let size: CGFloat
    let lockSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    // MARK: - Initializers

    init(space: some BrowserSpaceIdentifying, size: CGFloat, lockSize: CGFloat) {
        self.init(identity: space.identity, size: size, lockSize: lockSize)
    }

    init(identity: BrowserSpaceIdentity, size: CGFloat, lockSize: CGFloat) {
        self.identity = identity
        self.size = size
        self.lockSize = lockSize
    }

    var body: some View {
        Group {
            if let artwork = BrowserSpaceSymbolArtworkRenderer.shared.image(
                for: identity, size: size, lockSize: lockSize, colorScheme: colorScheme, scale: displayScale)
            {
                // The renderer already supplies this exact point size. Native
                // picker cells stretch resizable images to their label width.
                Image(decorative: artwork, scale: displayScale)
                    .renderingMode(.original)
                    .interpolation(.high)
            } else {
                BrowserSpaceSymbolArtworkContent(identity: identity, size: size, lockSize: lockSize)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
