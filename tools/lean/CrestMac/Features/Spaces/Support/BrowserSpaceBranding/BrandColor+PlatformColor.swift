import AppKit
import SwiftUI

extension BrandColor {
    init(color: Color) {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            self = .neutral
            return
        }
        self.init(
            clampingRed: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}
