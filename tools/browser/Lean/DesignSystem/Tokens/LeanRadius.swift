import CoreGraphics

/// Controlled corner radii. Lean uses tight chrome rather than pill-shaped content.
enum LeanRadius {
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let panel: CGFloat = 24
}
