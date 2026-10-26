import SwiftUI

struct PinnedTabInteractionSurface: ViewModifier {
    let favicon: FaviconAssets.Image?
    let siteTheme: BrowserTabIconAccent?
    let isSelected: Bool
    let isHovering: Bool
    var isMultiSelected = false
    var statusSource: BrowserTabStatusSource? = nil

    func body(content: Content) -> some View {
        content
            .background {
                BrowserTabStatusSurfaces(
                    tab: statusSource,
                    style: BrowserTabStatusSurfaceStyle(
                        accent: CrestBrandTheme.accent, cornerRadius: BrowserSidebarMetrics.layerCornerRadius(),
                        barOpacity: CrestOpacity.prominentStatusSurface))
            }
            .modifier(
                BrowserTabAppearanceSurface(
                    isPinned: true, isSelected: isSelected, isHovering: isHovering,
                    selectionEmphasis: isMultiSelected))
    }
}
