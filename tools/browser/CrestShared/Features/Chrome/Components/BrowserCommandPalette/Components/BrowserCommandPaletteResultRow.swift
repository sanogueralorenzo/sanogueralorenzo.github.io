import SwiftUI

struct BrowserCommandPaletteResultRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem
    /// The row names its kind at its end, as the blended layout shows it.
    var namesKind = false

    private var isSelected: Bool { model.selectedResultIndex == item.index }

    var body: some View {
        Button {
            model.activate(item.row)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                BrowserCommandPaletteRowIcon(model: model, row: item.row)

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

                BrowserCommandPaletteRowTrailing(
                    model: model, row: item.row, isSelected: isSelected, namesKind: namesKind)

                Image(systemName: isSelected ? model.selectedOpening.symbol : "arrow.right")
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: isSelected
            )
        )
        .accessibilityValue(model.engineBadge(for: item.row).map { Text($0.pageDescription) } ?? Text(verbatim: ""))
        .accessibilityHint(item.row.reason.map { Text($0.text) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("command-palette-result-\(item.index)")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#if DEBUG
    #Preview("Tab and command results") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        VStack(spacing: 4) {
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.tabItem)
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.commandItem)
        }.padding().frame(width: 600)
    }
#endif
