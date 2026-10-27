import AppKit
import SwiftUI

/// Monochrome chrome following the system's appearance.
enum CrestBrandTheme {
    static let canvas = gray(light: 1, dark: 0)
    static let surface = gray(light: 242.0 / 255, dark: 24.0 / 255)
    static let textDisplay = gray(light: 0, dark: 1)
    static let line = textDisplay.opacity(0.18)
    private static func gray(light: CGFloat, dark: CGFloat) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light, alpha: 1)
            })
    }
}
