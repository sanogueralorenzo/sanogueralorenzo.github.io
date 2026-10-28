import SwiftUI

enum SidebarGeometry {
    static let width = CGFloat(289)
    static let widthRange: ClosedRange<CGFloat> = 280...380
    static let inset: CGFloat = 6
    static let hoverMargin: CGFloat = 32
    static let titlebarHeight: CGFloat = 38
    static let titlebarHorizontalInset: CGFloat = 12
    static let navigationSymbolPointSize: CGFloat = 15
    static let rowHeight = LeanLayout.sidebarRowHeight

    static func windowCornerRadius(from insets: RectangleCornerInsets) -> CGFloat? {
        // Bottom corners describe the window; top insets can also reserve its controls.
        let radius = max(
            min(insets.bottomLeading.width, insets.bottomLeading.height),
            min(insets.bottomTrailing.width, insets.bottomTrailing.height))
        return radius > 0 ? radius : nil
    }

    static func radius(windowCornerRadius: CGFloat?) -> CGFloat {
        max(0, (windowCornerRadius ?? 13) - inset)
    }

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        width.isFinite ? min(max(width, widthRange.lowerBound), widthRange.upperBound) : self.width
    }
}

enum SpaceColors {
    static let names = ["Blue", "Teal", "Green", "Amber", "Coral", "Purple"]
    static let components: [(Double, Double, Double)] = [
        (0.23, 0.53, 0.96), (0.06, 0.69, 0.65), (0.2, 0.73, 0.37),
        (0.96, 0.66, 0.16), (0.96, 0.4, 0.36), (0.65, 0.39, 0.92),
    ]
}

extension Color {
    static func space(_ index: Int) -> Color {
        let rgb = SpaceColors.components[min(max(index, 0), SpaceColors.components.count - 1)]
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: 1)
    }
}
