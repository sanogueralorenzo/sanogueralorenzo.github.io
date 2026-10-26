import SwiftUI

extension EnvironmentValues {
    @Entry var folderPreviewShowsHighlight = false
    @Entry var folderUsesContrastingForeground = false
    @Entry var folderBackgroundColor: BrandColor? = nil
}

struct BrowserFolderHighlightSurface: ViewModifier {
    var showsFill = true
    var depth = 0
    var isSelected = false

    func body(content: Content) -> some View {
        content.background {
            if showsFill {
                RoundedRectangle(
                    cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous
                )
                .fill(isSelected ? CrestColor.selection : CrestColor.hover)
                .padding(.leading, BrowserFolderLayout.surfaceLeadingInset(depth: depth))
                .padding(.trailing, BrowserSidebarMetrics.layerInset)
                .allowsHitTesting(false)
            }
        }
    }
}
