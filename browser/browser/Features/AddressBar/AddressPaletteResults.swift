import SwiftUI

struct AddressPaletteResults: View {
    let results: [BrowserPaletteResult]
    let suggestions: [String]
    let searchProvider: SearchProvider
    let selection: Int?
    let cornerRadius: CGFloat
    let activateResult: (BrowserPaletteResult) -> Void
    let activateSuggestion: (String) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ViewThatFits(in: .vertical) {
            resultList
                .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    resultList
                }
                .onChange(of: selection, initial: true) { _, index in
                    if let index { proxy.scrollTo(index) }
                }
            }
        }
        .background {
            panelShape.fill(BrowserBrandTheme.surface)
                .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.20), radius: 14, y: 5)
        }
        .overlay { panelShape.strokeBorder(BrowserBrandTheme.line, lineWidth: 0.5) }
    }

    private var resultList: some View {
        VStack(spacing: 3) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                resultButton(selected: index == selection) {
                    activateResult(result)
                } label: {
                    row(title: result.title, subtitle: result.subtitle, symbol: result.symbol, spaceColor: result.spaceColor)
                }
                .id(index)
            }
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                resultButton(selected: results.count + index == selection) {
                    activateSuggestion(suggestion)
                } label: {
                    row(title: suggestion, subtitle: searchProvider.rawValue, symbol: "magnifyingglass")
                }
                .id(results.count + index)
            }
        }.padding(8)
    }

    private func resultButton<Label: View>(
        selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action, label: label)
            .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 12))
            .background(selected ? BrowserBrandTheme.line : .clear, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(title: String, subtitle: String, symbol: String, spaceColor: Int? = nil) -> some View {
        HStack(spacing: 12) {
            Group {
                if let spaceColor {
                    BrowserSpacePill(color: spaceColor)
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }.frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
    }
}
