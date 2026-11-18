import AppKit
import SwiftUI

struct AddressPalette: View {
    let store: BrowserStore
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var text: String
    init(store: BrowserStore, cornerRadius: CGFloat) {
        self.store = store
        self.cornerRadius = cornerRadius
        _text = State(initialValue: store.addressText)
    }
    @State private var suggestions: [String] = []
    @State private var selected: Int?
    @State private var siteSearch: SiteSearchMode?
    private struct SiteSearchMode {
        let search: BrowserSiteSearch
        let previousText: String
        let spaceID: UUID
    }
    private var results: [BrowserPaletteResult] { siteSearch == nil ? store.paletteResults(text) : [] }
    private var completionURL: URL? {
        guard siteSearch == nil, store.preferences.searchSuggestions, !store.activeSpace.isPrivate,
            text.count >= 2, !text.contains("://"), !text.hasPrefix(">")
        else { return nil }
        return store.preferences.searchProvider.suggestionsURL(for: text)
    }

    var body: some View {
        let results = results
        let completion = completionURL
        let selection = selectedIndex(resultCount: results.count)
        ZStack(alignment: .top) {
            backdrop
            VStack(spacing: 5) {
                editor
                if siteSearch == nil && (!results.isEmpty || !suggestions.isEmpty) {
                    resultsPanel(results, selection: selection)
                }
            }
            .frame(maxWidth: 525)
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 16)
        }
        .onChange(of: text) { selected = nil }
        .onChange(of: store.activeSpace.id) {
            if siteSearch != nil { cancel() }
        }
        .task(id: completion) { await loadSuggestions(from: completion) }
        .onExitCommand(perform: cancel)
    }

    private var backdrop: some View {
        let canvas = BrowserBrandTheme.canvas
        return Group {
            if reduceTransparency {
                canvas
            } else {
                LinearGradient(
                    stops: [
                        .init(color: canvas.opacity(0.95), location: 0),
                        .init(color: canvas.opacity(0.93), location: 0.61),
                        .init(color: canvas.opacity(0.86), location: 0.82),
                        .init(color: canvas.opacity(0.71), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .background { AddressFocusMaterial().allowsHitTesting(false) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: store.dismissAddress)
        .accessibilityHidden(true)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var editor: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
            Button(action: cancel) {
                Text("Esc")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(BrowserBrandTheme.line) }
            }
            .buttonStyle(BrowserChromeButtonStyle(controlSize: CGSize(width: 34, height: 28)))
            .accessibilityLabel("Cancel")
        }
        .padding(.leading, 15)
        .padding(.trailing, 9)
        .frame(height: 46)
        .background {
            panelShape.fill(BrowserBrandTheme.surface)
                .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.20), radius: 10, y: 3)
        }
        .overlay { panelShape.strokeBorder(BrowserBrandTheme.textDisplay.opacity(0.56), lineWidth: 1.25) }
    }

    private func resultsPanel(_ results: [BrowserPaletteResult], selection: Int?) -> some View {
        ViewThatFits(in: .vertical) {
            resultList(results, selection: selection)
                .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    resultList(results, selection: selection)
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

    private func resultList(_ results: [BrowserPaletteResult], selection: Int?) -> some View {
        let tabSelection = tabIndex(in: results, selection: selection)
        return VStack(spacing: 3) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                resultButton(selected: index == selection) {
                    perform(result)
                } label: {
                    row(
                        title: result.title, subtitle: result.subtitle, symbol: result.symbol, spaceColor: result.spaceColor,
                        showsSearchHint: index == tabSelection && knownSearch(for: result) != nil)
                }
                .id(index)
            }
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                resultButton(selected: results.count + index == selection) {
                    store.submitAddress(suggestion)
                } label: {
                    row(title: suggestion, subtitle: store.preferences.searchProvider.rawValue, symbol: "magnifyingglass")
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

    private func loadSuggestions(from url: URL?) async {
        suggestions = []
        guard let url else { return }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let values = try await BrowserSearchClient.shared.suggestions(from: url)
            guard !Task.isCancelled else { return }
            suggestions = Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(5))
        } catch {}
    }

    private func selectedIndex(resultCount: Int) -> Int? {
        let count = resultCount + suggestions.count
        if let selected, (0..<count).contains(selected) { return selected }
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
        guard let index = tabIndex(in: results, selection: selectedIndex(resultCount: results.count)),
            results[index].address != nil
        else { return false }
        let result = results[index]
        if let search = knownSearch(for: result) {
            siteSearch = SiteSearchMode(search: search, previousText: text, spaceID: store.activeSpace.id)
            text = ""
            suggestions = []
        } else {
            perform(result)
        }
        return true
    }
    private func tabIndex(in results: [BrowserPaletteResult], selection: Int?) -> Int? {
        guard let selection, results.indices.contains(selection) else { return nil }
        if selected == nil, results[selection].id == BrowserPaletteResult.webSearchID {
            return results.indices.dropFirst().first
        }
        return selection
    }
    private func knownSearch(for result: BrowserPaletteResult) -> BrowserSiteSearch? {
        guard let address = result.address else { return nil }
        return store.siteSearch(for: address, in: store.activeSpace.id)
    }
    private func cancel() {
        if let siteSearch {
            self.siteSearch = nil
            text = siteSearch.previousText
            selected = nil
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
            selected = nil
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
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddressFocusMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
