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
    @State private var siteSearch: BrowserSiteSearchShortcut?
    @State private var siteSearchText = ""

    private var offeredSiteSearch: BrowserSiteSearchShortcut? {
        guard siteSearch == nil, selected == nil else { return nil }
        return BrowserSiteSearchShortcut.matching(text)
    }
    private var results: [BrowserPaletteResult] { store.paletteResults(text) }
    private var completionURL: URL? {
        guard siteSearch == nil, store.preferences.searchSuggestions, !store.activeSpace.isPrivate,
            text.count >= 2, !text.contains("://"), !text.hasPrefix(">")
        else { return nil }
        return store.preferences.searchProvider.suggestionsURL(for: text)
    }

    var body: some View {
        let results = siteSearch == nil ? self.results : []
        let completion = completionURL
        let selection = selectedIndex(resultCount: results.count)
        ZStack(alignment: .top) {
            AddressPaletteBackdrop(dismiss: store.dismissAddress)
            VStack(spacing: 5) {
                editor
                if siteSearch == nil && (!results.isEmpty || !suggestions.isEmpty) {
                    AddressPaletteResults(
                        results: results, suggestions: suggestions, searchProvider: store.preferences.searchProvider,
                        selection: selection, cornerRadius: cornerRadius,
                        activateResult: perform, activateSuggestion: store.submitAddress
                    )
                }
            }
            .frame(maxWidth: 525)
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 16)
        }
        .onChange(of: text) { selected = nil }
        .task(id: completion) { await loadSuggestions(from: completion) }
        .onExitCommand(perform: cancel)
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
                Text("Search \(siteSearch.name)")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Divider().frame(height: 18)
            }
            BrowserAddressField(
                text: siteSearch == nil ? $text : $siteSearchText,
                prompt: siteSearch == nil ? "Search or Enter URL…" : "Search terms…",
                submit: submit, cancel: cancel, moveSelection: move, tab: tab
            ).frame(height: 28)
            if let shortcut = offeredSiteSearch {
                Button("Tab to search \(shortcut.name)") { siteSearch = shortcut }
                    .font(.caption)
                    .buttonStyle(BrowserChromeButtonStyle(controlSize: nil))
            }
            Button(action: cancel) {
                Text("Esc")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(BrowserBrandTheme.line) }
            }
            .buttonStyle(BrowserChromeButtonStyle(controlSize: CGSize(width: 34, height: 28)))
            .accessibilityLabel(siteSearch == nil ? "Cancel" : "Exit site search")
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
            if let url = siteSearch.searchURL(siteSearchText) { store.submitAddress(url) }
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
        if let shortcut = offeredSiteSearch {
            siteSearch = shortcut
            return true
        }
        let results = results
        if suggestions.isEmpty, results.allSatisfy(\.isWebSearch),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            submit()
            return true
        }
        guard let selection = selectedIndex(resultCount: results.count), results.indices.contains(selection)
        else { return false }
        let index = selected == nil && results[selection].isWebSearch ? selection + 1 : selection
        guard results.indices.contains(index), results[index].address != nil else { return false }
        perform(results[index])
        return true
    }

    private func cancel() {
        if siteSearch != nil {
            siteSearch = nil
            siteSearchText = ""
        } else {
            store.dismissAddress()
        }
    }

    private func perform(_ result: BrowserPaletteResult) {
        switch result.action {
        case .address(let url):
            store.submitAddress(url)
        case .splitTab(let id):
            guard let source = store.addressTarget?.splitSource else { return }
            if store.split(source, with: id) { store.dismissAddress() }
        case .perform(let action):
            store.dismissAddress()
            action(store)
        }
    }
}
