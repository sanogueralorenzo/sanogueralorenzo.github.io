import SwiftUI

struct AddressPalette: View {
    let store: BrowserStore
    @State private var text: String
    init(store: BrowserStore) {
        self.store = store
        _text = State(initialValue: store.addressText)
    }
    @State private var suggestions: [String] = []
    @State private var selected = -1
    private struct CompletionRequest: Hashable {
        let text: String
        let provider: SearchProvider
        let enabled: Bool
        let isPrivate: Bool
    }
    private var results: [BrowserPaletteResult] { store.paletteResults(text) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                BrowserAddressField(text: $text, submit: submit, cancel: store.dismissAddress, moveSelection: move)
                    .frame(height: 28)
                Button {
                    store.dismissAddress()
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(LeanChromeButtonStyle())
            }.padding(18)
            if !results.isEmpty || !suggestions.isEmpty {
                Divider()
                VStack(spacing: 3) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            perform(result)
                        } label: {
                            row(title: result.title, subtitle: result.subtitle, symbol: result.symbol)
                        }
                        .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 12))
                        .background(
                            index == selected ? LeanBrandTheme.line : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            store.submitAddress(suggestion)
                        } label: {
                            row(
                                title: suggestion, subtitle: store.preferences.searchProvider.rawValue,
                                symbol: "magnifyingglass")
                        }
                        .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 12))
                        .background(
                            results.count + index == selected ? LeanBrandTheme.line : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(8)
            }
        }.frame(width: 580)
            .background(LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).stroke(LeanBrandTheme.line, lineWidth: 0.5)
            }

            .onChange(of: text) { selected = -1 }
            .task(
                id: CompletionRequest(
                    text: text, provider: store.preferences.searchProvider,
                    enabled: store.preferences.searchSuggestions, isPrivate: store.activeSpace.isPrivate)
            ) {
                suggestions = []
                guard store.preferences.searchSuggestions, !store.activeSpace.isPrivate, text.count >= 2,
                    !text.contains("://"), !text.hasPrefix(">"),
                    let url = store.preferences.searchProvider.suggestionsURL(for: text)
                else { return }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let values = try await BrowserSearchSuggestionClient.shared.suggestions(from: url)
                    guard !Task.isCancelled else { return }
                    suggestions = Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(5))
                } catch {}
            }.onExitCommand { store.dismissAddress() }
    }
    private func move(_ direction: Int) {
        let count = results.count + suggestions.count
        guard count > 0 else { return }
        selected = (selected + direction + count) % count
    }
    private func submit() {
        if results.indices.contains(selected) {
            perform(results[selected])
        } else if selected >= results.count, suggestions.indices.contains(selected - results.count) {
            store.submitAddress(suggestions[selected - results.count])
        } else if text.hasPrefix(">"), let result = results.first {
            perform(result)
        } else {
            store.submitAddress(text)
        }
    }
    private func perform(_ result: BrowserPaletteResult) {
        // Close before executing: commands such as New Tab intentionally open another palette.
        store.addressPresented = false
        result.perform(store)
        if store.addressPresented {
            text = store.addressText
            selected = -1
            suggestions = []
        } else {
            store.pendingSplitSourceID = nil
        }
    }
    private func row(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }
}
