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
    @State private var siteSearch: SiteSearchMode?
    private struct SiteSearchMode {
        let search: BrowserSiteSearch
        let previousText: String
        let spaceID: UUID
    }
    private struct CompletionRequest: Hashable {
        let text: String
        let provider: SearchProvider
        let enabled: Bool
        let isPrivate: Bool
    }
    private var results: [BrowserPaletteResult] { siteSearch == nil ? store.paletteResults(text) : [] }
    var body: some View {
        let results = results
        let selection = selectedIndex(resultCount: results.count)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                if let siteSearch {
                    Text("Search \(siteSearch.search.name)")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: 220)
                        .fixedSize(horizontal: true, vertical: false)
                    Divider().frame(height: 18)
                }
                BrowserAddressField(
                    text: $text, prompt: siteSearch == nil ? "Search or Enter URL…" : "Search Terms…",
                    submit: submit, cancel: cancel, moveSelection: move, tab: tab
                ).frame(height: 28)
                Button {
                    store.dismissAddress()
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(BrowserChromeButtonStyle())
            }.padding(18)
            if siteSearch == nil && (!results.isEmpty || !suggestions.isEmpty) {
                Divider()
                VStack(spacing: 3) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            perform(result)
                        } label: {
                            row(
                                title: result.title, subtitle: result.subtitle, symbol: result.symbol,
                                spaceColor: result.spaceColor,
                                showsSearchHint: index == selection && knownSearch(for: result) != nil)
                        }
                        .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 12))
                        .background(
                            index == selection ? BrowserBrandTheme.line : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            store.submitAddress(suggestion)
                        } label: {
                            row(
                                title: suggestion, subtitle: store.preferences.searchProvider.rawValue,
                                symbol: "magnifyingglass")
                        }
                        .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 12))
                        .background(
                            results.count + index == selection ? BrowserBrandTheme.line : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(8)
            }
        }.frame(width: 580)
            .background(BrowserBrandTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).stroke(BrowserBrandTheme.line, lineWidth: 0.5)
            }

            .onChange(of: text) { selected = -1 }
            .onChange(of: store.activeSpace.id) {
                if siteSearch != nil { cancel() }
            }
            .task(
                id: CompletionRequest(
                    text: text, provider: store.preferences.searchProvider,
                    enabled: siteSearch == nil && store.preferences.searchSuggestions,
                    isPrivate: store.activeSpace.isPrivate)
            ) {
                suggestions = []
                guard siteSearch == nil, store.preferences.searchSuggestions, !store.activeSpace.isPrivate, text.count >= 2,
                    !text.contains("://"), !text.hasPrefix(">"),
                    let url = store.preferences.searchProvider.suggestionsURL(for: text)
                else { return }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let values = try await BrowserSearchClient.shared.suggestions(from: url)
                    guard !Task.isCancelled else { return }
                    suggestions = Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(5))
                } catch {}
            }.onExitCommand(perform: cancel)
    }
    private func selectedIndex(resultCount: Int) -> Int? {
        let count = resultCount + suggestions.count
        if (0..<count).contains(selected) { return selected }
        return count > 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : nil
    }
    private func move(_ direction: Int) {
        guard siteSearch == nil else { return }
        let resultCount = results.count
        let count = resultCount + suggestions.count
        guard count > 0 else { return }
        let current = selectedIndex(resultCount: resultCount) ?? (direction > 0 ? -1 : 0)
        selected = (current + direction + count) % count
    }
    private func submit() {
        if let siteSearch {
            guard siteSearch.spaceID == store.activeSpace.id, let url = siteSearch.search.url(for: text) else { return }
            store.submitAddress(url)
            return
        }
        let results = results
        guard let selected = selectedIndex(resultCount: results.count) else {
            store.submitAddress(text)
            return
        }
        if results.indices.contains(selected) {
            perform(results[selected])
        } else {
            store.submitAddress(suggestions[selected - results.count])
        }
    }
    private func tab() -> Bool {
        guard siteSearch == nil else { return false }
        let results = results
        guard let selected = selectedIndex(resultCount: results.count), results.indices.contains(selected),
            results[selected].address != nil
        else { return false }
        let result = results[selected]
        if let search = knownSearch(for: result) {
            siteSearch = SiteSearchMode(search: search, previousText: text, spaceID: store.activeSpace.id)
            text = ""
            suggestions = []
        } else {
            perform(result)
        }
        return true
    }
    private func knownSearch(for result: BrowserPaletteResult) -> BrowserSiteSearch? {
        guard let address = result.address else { return nil }
        return store.siteSearch(for: address, in: store.activeSpace.id)
    }
    private func cancel() {
        if let siteSearch {
            self.siteSearch = nil
            text = siteSearch.previousText
            selected = -1
        } else {
            store.dismissAddress()
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
    private func row(
        title: String, subtitle: String, symbol: String, spaceColor: Int? = nil, showsSearchHint: Bool = false
    ) -> some View {
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
            if showsSearchHint {
                Text("Tab to search").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }
}
