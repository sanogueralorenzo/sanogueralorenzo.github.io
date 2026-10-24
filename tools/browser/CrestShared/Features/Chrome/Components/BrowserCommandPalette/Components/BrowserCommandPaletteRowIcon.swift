import SwiftUI

struct BrowserCommandPaletteRowIcon: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow

    var body: some View {
        Group {
            if let tab = model.tab(for: row) {
                TabStateFaviconView(
                    tab: tab,
                    favicons: model.browser.core.state.favicons,
                    profileID: model.space?.profileID,
                    size: BrowserCommandPaletteMetrics.rowFaviconSize
                )
                .overlay(alignment: .bottomTrailing) {
                    TabEngineBadge(
                        tabID: tab.id,
                        scale: BrowserCommandPaletteMetrics.rowFaviconSize / TabFaviconMetrics.defaultSize)
                }
            } else if let provider = model.searchProvider(for: row) {
                BrowserSearchProviderIcon(
                    provider: provider,
                    profileID: model.space?.profileID,
                    size: BrowserCommandPaletteMetrics.rowFaviconSize
                )
            } else {
                Image(systemName: row.symbol)
                    .font(
                        .system(
                            size: BrowserCommandPaletteMetrics.rowSymbolPointSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: BrowserCommandPaletteMetrics.rowIconContainerSize,
            height: BrowserCommandPaletteMetrics.rowIconContainerSize
        )
        .background(
            .primary.opacity(BrowserCommandPaletteMetrics.rowIconBackgroundOpacity),
            in: .rect(cornerRadius: BrowserCommandPaletteMetrics.rowIconCornerRadius)
        )
    }
}

#if DEBUG
    #Preview("Result icons") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        HStack(spacing: 20) {
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.intentRow)
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.tabRow)
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.commandRow)
        }.padding()
    }
#endif
