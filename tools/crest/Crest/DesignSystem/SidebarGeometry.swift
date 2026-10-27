import SwiftUI

enum SidebarGeometry {
    static let width = CGFloat(289)
    static let inset: CGFloat = 6
    static let hoverMargin: CGFloat = 32
    static let radius: CGFloat = 6
    static let titlebarHeight: CGFloat = 36
    static let navigationSymbolPointSize: CGFloat = 15
    static let rowHeight = CrestLayout.sidebarRowHeight
}

extension Color {
    static func space(_ index: Int) -> Color {
        let palette: [UInt32] = [0x3B82F6, 0xF97316, 0xA855F7, 0x22C55E, 0xF43F5E, 0xEAB308]
        let rgb = palette[min(max(index, 0), palette.count - 1)]
        return Color(
            .sRGB, red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}
