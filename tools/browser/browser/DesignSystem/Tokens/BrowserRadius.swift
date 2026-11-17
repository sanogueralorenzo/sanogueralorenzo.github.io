import CoreGraphics

/// Controlled corner radii. Browser uses tight chrome rather than pill-shaped content.
enum BrowserRadius {
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let panel: CGFloat = 24
}
