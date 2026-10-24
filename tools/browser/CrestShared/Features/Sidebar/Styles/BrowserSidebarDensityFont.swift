import SwiftUI

struct BrowserSidebarDensityFont: ViewModifier {
    let scale: Double
    let supportsTouch: Bool
    @ScaledMetric(relativeTo: .body) private var textSizeScale = 1.0

    func body(content: Content) -> some View {
        let size =
            BrowserSidebarDensity.bodySize(touch: supportsTouch)
            * textSizeScale * BrowserSidebarDensity(scale).scale
        content.font(scale == 1 ? nil : .system(size: size))
    }
}
