import SwiftUI

/// Edits one search provider. A built-in keeps its address and offers only
/// its shortcuts; one the person adds or added offers its kind, name,
/// shortcuts, search and suggestion addresses and color, which a new one
/// takes from its own icon until the person picks one. The core checks every
/// field when the person saves.
struct BrowserSearchProviderEditor: View {
    let catalog: BrowserSearchCatalog
    var profileID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrowserSearchProviderDraft
    @State private var errorMessage: String?
    @FocusState private var nameIsFocused: Bool

    init(draft: BrowserSearchProviderDraft, catalog: BrowserSearchCatalog, profileID: UUID? = nil) {
        self.catalog = catalog
        self.profileID = profileID
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let builtIn = draft.builtIn {
                    builtInFields(builtIn)
                } else {
                    customFields
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("save-search-provider")
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
        .onAppear { nameIsFocused = draft.isNew }
        .task(id: draft.choseColor ? nil : host) {
            await takeColorFromIcon()
        }
    }

    private var title: LocalizedStringKey {
        if draft.builtIn != nil { return LocalizedStringKey(draft.name) }
        return draft.isNew ? "Add Provider" : "Edit Provider"
    }

    // MARK: - Fields

    @ViewBuilder
    private func builtInFields(_ builtIn: BuiltInSearchProvider) -> some View {
        Section {
            TextField(
                "Shortcuts", text: $draft.shortcuts, prompt: Text(verbatim: builtIn.shortcuts.joined(separator: ", "))
            )
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("search-provider-shortcuts")
            Button("Use Built-In Shortcuts") {
                draft.shortcuts = builtIn.shortcuts.joined(separator: ", ")
            }
            .disabled(draft.shortcutList == builtIn.shortcuts)
        } footer: {
            footer(hint: "Separate shortcuts with commas.")
        }
    }

    @ViewBuilder
    private var customFields: some View {
        Section {
            Picker("Kind", selection: $draft.kind) {
                ForEach(SearchProviderKind.all, id: \.self) { kind in
                    Text(kind.itemTitle).tag(kind)
                }
            }
            .accessibilityIdentifier("search-provider-kind")
            TextField("Name", text: $draft.name)
                .focused($nameIsFocused)
                .accessibilityIdentifier("search-provider-name")
            TextField("Shortcuts", text: $draft.shortcuts, prompt: Text(verbatim: "docs, d"))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("search-provider-shortcuts")
            TextField("Search URL", text: $draft.template, prompt: Text(verbatim: "https://example.com/search?q=%s"))
                .urlField()
                .accessibilityIdentifier("search-provider-url")
            TextField("Suggestions URL", text: $draft.suggestions, prompt: Text("Optional"))
                .urlField()
                .accessibilityIdentifier("search-provider-suggestions")
            ColorPicker("Color", selection: color, supportsOpacity: false)
                .accessibilityIdentifier("search-provider-color")
        } footer: {
            footer(hint: "Use \("%s") where the search words go.")
        }

        Section {
            BrowserSearchProviderPill(provider: SearchProvider(carried: draft.custom), profileID: profileID)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }

        if !draft.isNew {
            Section {
                Button("Remove Provider", role: .destructive) {
                    catalog.remove(draft.id)
                    dismiss()
                }
                .accessibilityIdentifier("remove-search-provider")
            }
        }
    }

    @ViewBuilder
    private func footer(hint: LocalizedStringKey) -> some View {
        if let errorMessage {
            Text(verbatim: errorMessage)
                .accessibilityIdentifier("search-provider-editor-error")
        } else {
            CrestFormFootnote(hint)
        }
    }

    private var color: Binding<Color> {
        Binding {
            draft.color.color
        } set: { value in
            let resolved = value.resolve(in: EnvironmentValues())
            draft.color = BrandColor(
                red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
            draft.choseColor = true
        }
    }

    /// The host of the address the person typed, without `www.`.
    private var host: String {
        SearchProvider(carried: draft.custom).site
    }

    // MARK: - Actions

    private func save() {
        do {
            if let builtIn = draft.builtIn {
                try catalog.setShortcuts(builtIn, draft.shortcutList == builtIn.shortcuts ? nil : draft.shortcutList)
            } else {
                try catalog.save(draft.custom)
            }
            dismiss()
        } catch let rejection as Rejection {
            errorMessage = BrowserCustomSearchProviderError(rejection).errorDescription
        } catch {
            errorMessage = error.personFacingDescription
        }
    }

    /// Gives a provider the person has not colored the main color of its icon.
    private func takeColorFromIcon() async {
        guard draft.builtIn == nil, !draft.choseColor, let profileID, !host.isEmpty,
            let page = URL(string: "https://\(host)/"),
            let data = await BrowserFaviconFallbackLoader.shared.data(for: page, profileID: profileID),
            let palette = BrowserFaviconPaletteExtractor().palette(imageData: data),
            !Task.isCancelled, !draft.choseColor
        else { return }
        draft.color = BrandColor(red: palette.primary.red, green: palette.primary.green, blue: palette.primary.blue)
    }
}

extension View {
    /// A field that takes a web address: no autocorrection, and on iPhone and
    /// iPad the URL keyboard without capitals.
    fileprivate func urlField() -> some View {
        #if os(iOS)
            keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}
