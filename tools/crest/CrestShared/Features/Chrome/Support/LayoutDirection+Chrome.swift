import SwiftUI

extension LayoutDirection {
    // MARK: - Actions - Chrome

    /// `distance` towards the leading edge, as a physical horizontal offset.
    func leadingOffset(_ distance: CGFloat) -> CGFloat {
        self == .leftToRight ? distance : -distance
    }

    func sidebarResizeDelta(_ translation: CGFloat) -> CGFloat {
        semanticHorizontalTranslation(translation)
    }

    func semanticHorizontalTranslation(_ translation: CGFloat) -> CGFloat {
        leadingOffset(translation)
    }

    func isLeadingEdgeReveal(_ translation: CGSize) -> Bool {
        let inwardDistance = semanticHorizontalTranslation(translation.width)
        return inwardDistance > 45
            && abs(translation.width) > abs(translation.height)
    }
}
