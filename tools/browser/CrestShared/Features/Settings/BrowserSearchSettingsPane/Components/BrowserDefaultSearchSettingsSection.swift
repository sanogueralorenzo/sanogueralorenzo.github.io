import SwiftUI

/// The search every Space follows unless it chose its own, the one private
/// windows follow, whether the default suggests searches, and whether Tab
/// after a shortcut searches its provider.
struct BrowserDefaultSearchSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore
    let catalog: BrowserSearchCatalog
    var profileID: UUID? = nil

    var body: some View {
        Section {
            Picker("Default search", selection: defaultProvider) {
                ForEach(catalog.defaultChoices) { provider in
                    BrowserSearchProviderIdentityLabel(provider: provider, profileID: profileID)
                        .tag(Optional(provider))
                }
            }
            .accessibilityIdentifier("default-search")

            Picker("Private windows", selection: privateProvider) {
                ForEach(catalog.defaultChoices) { provider in
                    BrowserSearchProviderIdentityLabel(provider: provider, profileID: profileID)
                        .tag(Optional(provider))
                }
            }
            .accessibilityIdentifier("private-search")

            Toggle("Search suggestions", isOn: suggestions)
                .accessibilityIdentifier("default-search-suggestions")

            Toggle(isOn: $preferences.palette.searchesSitesWithTab) {
                Text("Tab to search providers")
                Text("Type a provider’s name or shortcut and press Tab, or type $ and its shortcut, then a space.")
            }
            .accessibilityIdentifier("palette-tab-to-search")
        } header: {
            Text("Search")
        } footer: {
            CrestFormFootnote(
                "Each device keeps its own default search. Search suggestions send what you type to the search engine.")
        }
    }

    private var defaultProvider: Binding<SearchProvider?> {
        Binding {
            catalog.defaultProvider
        } set: { provider in
            guard let provider else { return }
            try? catalog.setDefault(provider)
        }
    }

    private var privateProvider: Binding<SearchProvider?> {
        Binding {
            catalog.privateDefaultProvider
        } set: { provider in
            guard let provider else { return }
            try? catalog.setPrivateDefault(provider)
        }
    }

    private var suggestions: Binding<Bool> {
        Binding {
            catalog.suggestionsEnabled
        } set: {
            catalog.setSuggestionsEnabled($0)
        }
    }
}
