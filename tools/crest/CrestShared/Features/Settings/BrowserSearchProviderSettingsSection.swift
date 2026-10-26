import SwiftUI

struct BrowserSearchProviderSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Search") {
            Picker("Search provider", selection: $preferences.searchProvider) {
                ForEach(SearchProvider.all) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .accessibilityIdentifier("search-provider-picker")

            Toggle("Search suggestions", isOn: $preferences.searchSuggestionsEnabled)
                .accessibilityIdentifier("default-search-suggestions")
        }
    }
}
