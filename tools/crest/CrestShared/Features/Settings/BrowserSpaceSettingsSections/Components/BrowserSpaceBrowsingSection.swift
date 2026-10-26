import SwiftUI

/// What a Space searches with, whether it suggests searches, and when it
/// archives current tabs. Search and suggestions follow the device's default
/// until the Space chooses its own; the providers themselves live in
/// Settings › Search.
struct BrowserSpaceBrowsingSection: View {
    let browser: BrowserStore
    let space: SpaceModel
    let dismissKeyboard: @MainActor () -> Void
    let pickerPresentation: BrowserSpaceBrowsingPickerPresentationStyle

    @State private var catalog: BrowserSearchCatalog

    init(
        browser: BrowserStore,
        space: SpaceModel,
        dismissKeyboard: @escaping @MainActor () -> Void = {},
        pickerPresentation: BrowserSpaceBrowsingPickerPresentationStyle = BrowserPlatformSearchEnginePresentation
            .pickerStyle
    ) {
        self.browser = browser
        self.space = space
        self.dismissKeyboard = dismissKeyboard
        self.pickerPresentation = pickerPresentation
        _catalog = State(initialValue: BrowserSearchCatalog(core: browser.core))
    }

    var body: some View {
        Section {
            searchPicker
            suggestionsPicker
            cleanupPolicyPicker

            Button("Archive Now") {
                browser.cleanupCurrentTabs(in: space.id)
            }
            .disabled(currentPreferences.currentTabCleanup == .never)
        } header: {
            Text("Browsing")
        } footer: {
            CrestFormFootnote("Search suggestions send what you type to the search engine.")
        }
    }

    private var currentPreferences: BrowsingPreferences {
        space.settings.browsingPreferences
    }

    private var cleanupPolicyBinding: Binding<CurrentTabCleanup> {
        browser.browsingPreferenceBinding(\.currentTabCleanup, in: space)
    }

    // MARK: - Search

    /// The Space's choice: the default while it follows it, else its own.
    private var searchChoice: Binding<BrowserSpaceSearchChoice> {
        Binding {
            BrowserSpaceSearchChoice(
                provider: currentPreferences.followsDefaultSearch
                    ? nil : catalog.provider(for: currentPreferences, isPrivate: browser.isPrivateBrowsing))
        } set: { choice in
            dismissKeyboard()
            browser.setSearch(choice.provider, suggestions: suggestionChoice.wrappedValue.enabled, in: space.id)
        }
    }

    /// Default, then every engine and assistant the device offers, and the
    /// Space's own when the device no longer offers it.
    private var searchChoices: [BrowserSpaceSearchChoice] {
        var providers = catalog.defaultChoices
        if let own = searchChoice.wrappedValue.provider, !providers.contains(own) { providers.append(own) }
        return [BrowserSpaceSearchChoice(provider: nil)] + providers.map { BrowserSpaceSearchChoice(provider: $0) }
    }

    private func title(of choice: BrowserSpaceSearchChoice) -> String {
        if let provider = choice.provider { return provider.title }
        return String(
            localized: "Default (\(catalog.defaultProvider(isPrivate: browser.isPrivateBrowsing)?.title ?? "Google"))",
            comment: "A Space follows the device's default search, named in parentheses.")
    }

    /// The same picker as the default search's, each choice in its
    /// provider's icon; the default wears the icon of the provider it follows.
    private var searchPicker: some View {
        Picker("Search with", selection: searchChoice) {
            ForEach(searchChoices) { choice in
                if let provider = choice.provider ?? catalog.defaultProvider(isPrivate: browser.isPrivateBrowsing) {
                    BrowserSearchProviderIdentityLabel(
                        provider: provider, profileID: space.profileID, title: title(of: choice)
                    )
                    .tag(choice)
                } else {
                    Text(title(of: choice)).tag(choice)
                }
            }
        }
        .accessibilityIdentifier("space-search-provider")
    }

    // MARK: - Suggestions

    private var suggestionChoice: Binding<BrowserSpaceSuggestionChoice> {
        Binding {
            currentPreferences.followsDefaultSuggestions
                ? .followsDefault : BrowserSpaceSuggestionChoice(enabled: currentPreferences.searchSuggestionsEnabled)
        } set: { choice in
            browser.setSearch(searchChoice.wrappedValue.provider, suggestions: choice.enabled, in: space.id)
        }
    }

    private var suggestionsPicker: some View {
        BrowserSpaceBrowsingPreferencePicker(
            title: "Search suggestions",
            presentation: pickerPresentation,
            selection: suggestionChoice,
            choices: BrowserSpaceSuggestionChoice.all,
            choiceTitle: { $0.title(defaultEnabled: catalog.suggestionsEnabled) },
            accessibilityIdentifier: "space-search-suggestions",
            dismissKeyboard: dismissKeyboard,
            choiceLabel: { choice in
                Text(choice.title(defaultEnabled: catalog.suggestionsEnabled))
            },
            selectedValue: {
                Text(suggestionChoice.wrappedValue.title(defaultEnabled: catalog.suggestionsEnabled))
                    .foregroundStyle(.secondary)
            })
    }

    // MARK: - Cleanup

    private var cleanupPolicyPicker: some View {
        BrowserSpaceBrowsingPreferencePicker(
            title: "Archive current tabs",
            presentation: pickerPresentation,
            selection: cleanupPolicyBinding,
            choices: CurrentTabCleanup.all,
            choiceTitle: { String(localized: $0.title) },
            accessibilityIdentifier: "space-tab-cleanup-policy",
            dismissKeyboard: dismissKeyboard,
            choiceLabel: { policy in
                Text(policy.title)
            },
            selectedValue: {
                Text(currentPreferences.currentTabCleanup.title)
                    .foregroundStyle(.secondary)
            })
    }
}

extension CurrentTabCleanup: Identifiable {
    var id: String { name }
}
