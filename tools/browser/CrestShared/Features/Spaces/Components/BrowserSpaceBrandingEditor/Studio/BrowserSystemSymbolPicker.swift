import SwiftUI

struct BrowserSystemSymbolPicker: View {
    @Binding var selection: String
    var loadNames: @MainActor () async -> [String] = { await BrowserSystemSymbolCatalog.availableNames() }
    @State private var isPresented = false

    var body: some View {
        BrowserArtworkPickerButton(
            title: "SF Symbol", detail: selection.isEmpty ? Text("Browse symbols") : Text(verbatim: selection)
        ) {
            isPresented = true
        } artwork: {
            Image(systemName: selection.isEmpty ? "square.grid.2x2" : selection)
        }
        .accessibilityLabel("Choose SF Symbol")
        .accessibilityValue(selection)
        .help(selection.isEmpty ? "Choose an SF Symbol" : selection)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            BrowserSystemSymbolCatalogPicker(selection: $selection, loadNames: loadNames)
                .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct BrowserSystemSymbolCatalogPicker: View {
    @Binding var selection: String
    var loadNames: @MainActor () async -> [String] = { await BrowserSystemSymbolCatalog.availableNames() }
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SF Symbols").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            BrowserSystemSymbolCatalogGrid(selection: selection, query: query, loadNames: loadNames) { name in
                selection = name
                dismiss()
            }
        }
        .padding(20)
        .frame(idealWidth: 480, maxWidth: 520, idealHeight: 500, maxHeight: 600)
        .task {
            searchFocused = true
        }
    }
}

/// Shared searchable catalog for Space artwork and sidebar folder icons.
struct BrowserSystemSymbolCatalogGrid: View {
    let selection: String?
    let query: String
    var loadNames: @MainActor () async -> [String] = { await BrowserSystemSymbolCatalog.availableNames() }
    let select: (String) -> Void
    @State private var names: [String] = []
    @State private var isLoading = true

    private var matches: [String] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "." })
        return words.isEmpty ? names : names.filter { name in words.allSatisfy { name.contains($0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(matches, id: \.self) { name in
                        Button {
                            select(name)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: name)
                                    .resizable().scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .frame(height: 36)
                                Text(name.replacingOccurrences(of: ".", with: " "))
                                    .font(.caption2).lineLimit(2).frame(height: 30)
                            }
                            .frame(maxWidth: .infinity).padding(8)
                            .background(
                                selection == name ? Color.accentColor.opacity(0.12) : .primary.opacity(0.035),
                                in: .rect(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10).strokeBorder(
                                    selection == name ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain).help(name)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(selection == name ? .isSelected : [])
                    }
                }
                .padding(2)
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading symbols…")
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            Text("\(matches.count) symbols").font(.caption).foregroundStyle(.secondary)
        }
        .task {
            names = await loadNames()
            isLoading = false
        }
    }
}

#if DEBUG
    #Preview("Choose a symbol") {
        @Previewable @State var symbol = "briefcase.fill"
        BrowserSystemSymbolPicker(
            selection: $symbol,
            loadNames: { ["briefcase.fill", "house.fill", "star.fill", "globe", "leaf.fill", "heart.fill"] }
        ).padding().frame(width: 360, height: 460)
    }
#endif

#if DEBUG
    #Preview("Symbol catalog") {
        @Previewable @State var selection = "briefcase.fill"
        @Previewable @State var query = ""
        VStack {
            TextField("Search symbols", text: $query)
            BrowserSystemSymbolCatalogGrid(
                selection: selection, query: query,
                loadNames: {
                    ["briefcase.fill", "house.fill", "star.fill", "globe", "leaf.fill", "heart.fill"]
                }, select: { selection = $0 })
        }.padding().frame(width: 480, height: 500)
    }
#endif
