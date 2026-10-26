import Foundation

struct BrowserPeekSourcePresentation: Codable, Equatable, Hashable, Sendable {
    let normalizedMinX: Double
    let normalizedMinY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double
    let normalizedTouchX: Double
    let normalizedTouchY: Double
    let label: String

    init(
        normalizedMinX: Double,
        normalizedMinY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        normalizedTouchX: Double? = nil,
        normalizedTouchY: Double? = nil,
        label: String
    ) {
        let minX = Self.normalizedValue(normalizedMinX)
        let minY = Self.normalizedValue(normalizedMinY)
        let width = Self.normalizedValue(normalizedWidth)
        let height = Self.normalizedValue(normalizedHeight)
        self.normalizedMinX = minX
        self.normalizedMinY = minY
        self.normalizedWidth = min(width, 1 - minX)
        self.normalizedHeight = min(height, 1 - minY)
        self.normalizedTouchX = Self.normalizedValue(
            normalizedTouchX ?? minX + self.normalizedWidth / 2
        )
        self.normalizedTouchY = Self.normalizedValue(
            normalizedTouchY ?? minY + self.normalizedHeight / 2
        )
        self.label = String(
            label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160)
        )
    }

    /// The source a touch at `touchPoint` in a web view of `webViewSize`
    /// names, or nil for a point outside it. `hasTopLeadingOrigin` says
    /// whether the view's y axis runs down from its top.
    init?(
        touchPoint: CGPoint,
        in webViewSize: CGSize,
        hasTopLeadingOrigin: Bool,
        label: String
    ) {
        guard webViewSize.width > 0,
            webViewSize.height > 0,
            touchPoint.x.isFinite,
            touchPoint.y.isFinite
        else { return nil }

        let normalizedX = touchPoint.x / webViewSize.width
        let normalizedY =
            hasTopLeadingOrigin
            ? touchPoint.y / webViewSize.height
            : 1 - touchPoint.y / webViewSize.height
        guard (0...1).contains(normalizedX),
            (0...1).contains(normalizedY)
        else { return nil }

        self.init(
            normalizedMinX: normalizedX,
            normalizedMinY: normalizedY,
            normalizedWidth: 0,
            normalizedHeight: 0,
            normalizedTouchX: normalizedX,
            normalizedTouchY: normalizedY,
            label: label
        )
    }

    static func resolved(
        _ sourcePresentation: BrowserPeekSourcePresentation?
    ) -> BrowserPeekSourcePresentation {
        sourcePresentation
            ?? BrowserPeekSourcePresentation(
                normalizedMinX: 0.5,
                normalizedMinY: 0.5,
                normalizedWidth: 0,
                normalizedHeight: 0,
                normalizedTouchX: 0.5,
                normalizedTouchY: 0.5,
                label: "Browser center"
            )
    }

    private static func normalizedValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
