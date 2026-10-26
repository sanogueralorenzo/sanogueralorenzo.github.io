import SwiftUI

extension View {
    /// Applies folder indentation and density while allowing accessible text to grow.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserFolderGroupConfiguration
    ) -> some View {
        modifier(BrowserFolderHeaderDensityLayout(configuration: configuration))
    }
}

private struct BrowserFolderHeaderDensityLayout: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let metrics = configuration.headerMetrics
        let height = BrowserSidebarDensity(dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale).rowHeight(
            base: CrestLayout.sidebarRowHeight, touch: !metrics.usesFixedRowHeight)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, configuration.headerLeadingInset)
            .padding(.trailing, metrics.contentTrailingInset)
            .frame(
                minHeight: height,
                maxHeight: metrics.usesFixedRowHeight && !dynamicTypeSize.isAccessibilitySize
                    ? height
                    : nil
            )
    }
}
