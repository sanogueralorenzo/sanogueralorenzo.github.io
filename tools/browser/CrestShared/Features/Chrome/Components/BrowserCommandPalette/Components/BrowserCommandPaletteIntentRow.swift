import SwiftUI

/// A row the palette leads with or runs as typed: the best match, the
/// address or search for the text, a search provider, a calculation or a pasted
/// address. It shows larger, and its end says where Return opens it.
struct BrowserCommandPaletteIntentRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem

    private var isSelected: Bool { model.selectedResultIndex == item.index }

    var body: some View {
        Button {
            model.activate(item.row)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                Group {
                    if model.tab(for: item.row) != nil {
                        BrowserCommandPaletteRowIcon(model: model, row: item.row)
                    } else if let provider = model.searchProvider(for: item.row) {
                        BrowserSearchProviderIcon(
                            provider: provider,
                            profileID: model.space?.profileID,
                            size: BrowserCommandPaletteMetrics.intentSymbolPointSize
                        )
                    } else {
                        Image(systemName: item.row.symbol)
                            .font(
                                .system(
                                    size: BrowserCommandPaletteMetrics.intentSymbolPointSize,
                                    weight: .semibold
                                )
                            )
                    }
                }
                .frame(
                    width: BrowserCommandPaletteMetrics.rowIconContainerSize,
                    height: BrowserCommandPaletteMetrics.rowIconContainerSize
                )
                .background(
                    .primary.opacity(
                        BrowserCommandPaletteMetrics.rowIconBackgroundOpacity
                    ),
                    in: .rect(
                        cornerRadius: BrowserCommandPaletteMetrics.rowIconCornerRadius
                    )
                )
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: BrowserCommandPaletteMetrics.rowTextSpacing
                ) {
                    Text(verbatim: item.row.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    BrowserCommandPaletteRowDetail(model: model, row: item.row)
                }

                Spacer(minLength: BrowserCommandPaletteMetrics.rowSpacing)

                BrowserCommandPaletteRowTrailing(model: model, row: item.row, isSelected: isSelected)

                Image(systemName: isSelected ? model.selectedOpening.symbol : "arrow.turn.down.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: isSelected
            )
        )
        .accessibilityLabel(Text(verbatim: item.row.title))
        .accessibilityValue(Text(verbatim: item.row.subtitle))
        .accessibilityHint(item.row.reason.map { Text($0.text) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("command-palette-primary-action")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#if DEBUG
    #Preview("Search intent") {
        BrowserCommandPaletteIntentRow(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"),
            item: BrowserCommandPalettePreviewFixture.intentItem
        )
        .padding().frame(width: 600)
    }
#endif
