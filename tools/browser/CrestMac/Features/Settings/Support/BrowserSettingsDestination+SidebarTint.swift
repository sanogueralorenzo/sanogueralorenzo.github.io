import AppKit
import SwiftUI

extension BrowserSettingsDestination {
    /// The sidebar icon's tint: the destination's tincture at a brightness
    /// the sidebar reads at.
    var sidebarTint: Color { tincture.color.sidebarIconColor }
}

extension BrandColor {
    /// The color at a brightness a sidebar glyph reads at: the templates'
    /// deep tinctures are lifted in Dark Mode, and their bright metals dimmed
    /// in Light Mode, keeping the hue. A lifted tincture gives up some
    /// saturation, so it stays as muted as the template it comes from.
    fileprivate var sidebarIconColor: Color {
        let base = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let shown = isDark ? max(brightness, 0.72) : min(max(brightness, 0.4), 0.68)
                let muted = shown > brightness ? saturation * 0.62 : saturation
                return NSColor(hue: hue, saturation: muted, brightness: shown, alpha: 1)
            })
    }
}
