import SwiftUI

/// The folder's symbol, in the same column the rows below give their favicons.
struct BrowserFolderIcon: View {
    let folder: FolderStateModel
    let isExpanded: Bool
    let metrics: BrowserFolderHeaderMetrics
    @AppStorage(BrowserFolderAppearancePreference.iconOnlyKey, store: BrowserFolderAppearancePreference.defaults)
    private var iconOnly = BrowserLookAndFeelDefaults.foldersIconOnly

    var body: some View {
        BrowserFolderArtwork(symbol: folder.displaySymbol, color: folder.displayColor, isExpanded: isExpanded)
            .modifier(
                BrowserFolderIconColumn(
                    metrics: metrics,
                    isExpanded: isExpanded
                        && !(iconOnly && BrowserFolderArtwork.customGlyph(for: folder.displaySymbol) != nil)
                )
            )
            .accessibilityHidden(true)
    }
}

/// Applies the saved folder artwork preference to the shared drawing.
struct BrowserFolderArtwork: View {
    let symbol: String
    let color: BrandColor
    var isExpanded = false
    @AppStorage(BrowserFolderAppearancePreference.iconOnlyKey, store: BrowserFolderAppearancePreference.defaults)
    private var iconOnly = BrowserLookAndFeelDefaults.foldersIconOnly
    @AppStorage(BrowserFolderAppearancePreference.tintsTitleKey, store: BrowserFolderAppearancePreference.defaults)
    private var tintsTitle = BrowserLookAndFeelDefaults.foldersTintTitle

    var body: some View {
        BrowserFolderArtworkContent(
            symbol: symbol, color: color, isExpanded: isExpanded, iconOnly: iconOnly, tintsTitle: tintsTitle)
    }

    static func customGlyph(for symbol: String) -> Text? {
        BrowserFolderArtworkContent.customGlyph(for: symbol)
    }
}

/// Holds the symbol in its column, and sizes it where the shell reads the row
/// from further away than a desk.
private struct BrowserFolderIconColumn: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics
    let isExpanded: Bool
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var iconScale = 1.0

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
