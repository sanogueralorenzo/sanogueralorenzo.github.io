import CoreGraphics

/// Fits Space icons to their strip, then scrolls at the minimum size.
enum BrowserSpaceIconSizing {
    private static let fittingScales: [CGFloat] = stride(from: 100, through: 30, by: -5).map { CGFloat($0) / 100 }

    static func scale(spaceCount: Int, style: CrestSpaceIconPickerStyle, width: CGFloat) -> CGFloat {
        let widths = fittingScales.map { ($0, style.scaled(by: $0).contentWidth(spaceCount: spaceCount)) }
        if let fitting = widths.first(where: { $0.1 <= width }) { return fitting.0 }
        return widths.min { $0.1 < $1.1 }?.0 ?? 1
    }
}
