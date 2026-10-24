import SwiftUI

struct BrowserCommandPaletteResultList: View {
    let model: BrowserCommandPaletteModel
    let maximumResultAreaHeight: CGFloat
    /// The results take all the height they may, however few there are.
    var fillsHeight = false

    private var resultAreaHeight: CGFloat {
        guard !fillsHeight else { return maximumResultAreaHeight }
        return BrowserCommandPaletteLayout.resultAreaHeight(
            groups: model.groups.map { ($0.section.title != nil, $0.items.count) },
            maximumHeight: maximumResultAreaHeight
        )
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: BrowserCommandPaletteMetrics.resultGroupSpacing
                ) {
                    ForEach(model.groups) { group in
                        BrowserCommandPaletteResultGroupView(
                            model: model,
                            group: group
                        )
                    }
                }
                .padding(BrowserCommandPaletteMetrics.resultContentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: resultAreaHeight)
            .clipped()
            .onChange(of: model.keyboardSelectionRevision) { _, _ in
                revealSelection(using: reader)
            }
            .onChange(of: model.items) { _, _ in
                revealSelection(using: reader)
            }
        }
    }

    private func revealSelection(using reader: ScrollViewProxy) {
        guard model.items.indices.contains(model.selectedResultIndex) else { return }
        // A nil anchor moves only as far as needed to reveal the row. Hover
        // selection deliberately does not initiate scrolling under the pointer.
        reader.scrollTo(model.items[model.selectedResultIndex].id)
    }
}
