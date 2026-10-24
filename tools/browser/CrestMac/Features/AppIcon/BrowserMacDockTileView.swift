import AppKit

/// What Crest draws in its Dock tile: its app icon, and below it, how far the
/// downloads in progress are. Both the running app and the Dock tile plug-in,
/// which draws the tile while the app is not running, draw it this way.
final class BrowserMacDockTileView: NSView {
    // MARK: - Variables

    /// The icon, fitted to the tile.
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    /// How far the downloads in progress are, from zero to one, or nil for no
    /// bar.
    var progress: Double? {
        didSet { needsDisplay = true }
    }

    // MARK: - Actions - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let image {
            image.draw(in: fitted(image.size), from: .zero, operation: .sourceOver, fraction: 1)
        }
        if let progress { drawBar(at: min(max(progress, 0), 1)) }
    }

    /// The largest rectangle of `size`'s proportions centered in the tile.
    private func fitted(_ size: NSSize) -> NSRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width,
            height: fitted.height)
    }

    /// A rounded bar across the bottom of the icon, filled to `fraction`.
    private func drawBar(at fraction: Double) {
        let track = NSRect(
            x: bounds.width * 0.14, y: bounds.height * 0.1, width: bounds.width * 0.72, height: bounds.height * 0.1)
        let radius = track.height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let inset = track.insetBy(dx: track.height * 0.15, dy: track.height * 0.15)
        guard fraction > 0 else { return }
        let fill = NSRect(
            x: inset.minX, y: inset.minY, width: max(inset.height, inset.width * fraction), height: inset.height)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }
}
