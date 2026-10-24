import SwiftUI

/// Finds a heraldic emblem by name and puts it on the crest.
struct BrowserCrestStudioHeraldicEmblemControls: View {
    let context: BrowserCrestStudioContext
    @Binding var search: String
    @Binding var showsAll: Bool

    var body: some View {
        let matches = CrestSymbol.selectable.filter {
            search.isEmpty || String(localized: $0.title).localizedCaseInsensitiveContains(search)
        }
        let visible = search.isEmpty && !showsAll ? Array(matches.prefix(12)) : matches
        BrowserCrestStudioTextField(title: "Find an emblem", symbol: "magnifyingglass", text: $search)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 8) {
            ForEach(visible, id: \.self) { choice in
                BrowserCrestStudioChoice(
                    title: choice.title, selected: context.value.crest.resolvedCharge == .heraldic(choice)
                ) {
                    context.branding.editorUpdate {
                        $0.crest.symbol = choice
                        $0.crest.charge = nil
                        $0.hasCustomAppearance = true
                    }
                } artwork: {
                    BrowserSpaceCrestIcon(
                        branding: context.preview {
                            $0.crest.symbol = choice
                            $0.crest.charge = nil
                        }, size: 52, rasterizesLayers: false
                    )
                    .equatable()
                }
            }
        }
        if search.isEmpty && matches.count > 12 {
            Button(showsAll ? "Show fewer emblems" : "Browse all emblems (\(matches.count))") { showsAll.toggle() }
                .buttonStyle(.borderless)
        } else if matches.isEmpty {
            Text("No matching emblems. Try an SF Symbol or a monogram.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
