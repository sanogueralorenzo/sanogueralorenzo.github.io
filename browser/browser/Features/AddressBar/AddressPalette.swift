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
    private var results: [BrowserPaletteResult] { store.paletteResults(text) }
    private var completionURL: URL? {
        guard store.preferences.searchSuggestions, !store.activeSpace.isPrivate,
            text.count >= 2, !text.contains("://"), !text.hasPrefix(">")
        else { return nil }
        return store.preferences.searchProvider.suggestionsURL(for: text)
    }

    var body: some View {
        let results = results
        let completion = completionURL
        let selection = selectedIndex(resultCount: results.count)
        ZStack(alignment: .top) {
            AddressPaletteBackdrop(dismiss: store.dismissAddress)
            VStack(spacing: 5) {
                editor
                if !results.isEmpty || !suggestions.isEmpty {
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
        .onExitCommand(perform: store.dismissAddress)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var editor: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            BrowserAddressField(
                text: $text, prompt: "Search or Enter URL…",
                submit: submit, cancel: store.dismissAddress, moveSelection: move, tab: tab
            ).frame(height: 28)
            Button(action: store.dismissAddress) {
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
        let resultCount = results.count
        let count = resultCount + suggestions.count
        guard count > 0 else { return }
        let current = selectedIndex(resultCount: resultCount) ?? (direction > 0 ? -1 : 0)
        selected = (current + direction + count) % count
    }
    private func submit() {
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
    private func perform(_ result: BrowserPaletteResult) {
        // Close first so commands like New Tab can open a fresh palette.
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
}
