import AppKit

extension BrowserSpaceArtworkRenderer {
    // MARK: - Static Variables

    /// The side of a Space's icon in an AppKit menu, in points.
    static let menuIconSize: CGFloat = 16

    // MARK: - Actions - Menus

    /// The icon an AppKit menu item shows for `space`, such as a Space in the
    /// Dock menu or in a page's context menu, drawn for the main screen.
    func menuImage(for space: BrowserSpaceIdentity) -> NSImage? {
        let size = Self.menuIconSize
        guard
            let image = image(
                for: space, size: size,
                scale: NSScreen.main?.backingScaleFactor ?? 2)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}
