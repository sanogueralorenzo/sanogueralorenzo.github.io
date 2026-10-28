import SwiftUI

/// The folder's symbol, in the same column the rows below give their favicons.
struct BrowserFolderIcon: View {
    let isExpanded: Bool
    let metrics: BrowserFolderHeaderMetrics
    var body: some View {
        BrowserFolderArtwork(isExpanded: isExpanded)
            .modifier(BrowserFolderIconColumn(metrics: metrics, isExpanded: isExpanded))
            .accessibilityHidden(true)
    }
}

/// The same standard folder artwork in the sidebar, menus and drag previews.
struct BrowserFolderArtwork: View {
    var isExpanded = false

    var body: some View { BrowserFolderArtworkContent(isExpanded: isExpanded) }
}

/// Holds the symbol in its column, and sizes it where the shell reads the row
/// from further away than a desk.
private struct BrowserFolderIconColumn: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics
    let isExpanded: Bool
    private let iconScale = 1.0

    func body(content: Content) -> some View {
        content
            .font(
                .system(
                    size: ((metrics.iconGlyphSize ?? 16) + 2) * BrowserSidebarDensity(iconScale).scale,
                    weight: metrics.iconGlyphWeight)
            )
            // Reserve the open front's projected edge without moving the title
            // when the folder toggles. The bottom hinge lowers its optical center.
            .offset(y: (isExpanded ? -1.5 : -0.5) * BrowserSidebarDensity(iconScale).scale)
            .frame(width: (metrics.iconWidth + 6) * BrowserSidebarDensity(iconScale).scale)
    }
}
