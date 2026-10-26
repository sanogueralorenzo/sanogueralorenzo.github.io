import SwiftUI

/// Search on this device: the default search every Space follows unless it
/// chose its own, how the command palette ranks and arranges what it offers
/// and what it learns, then every search provider with its shortcuts and
/// options, the longest list, last.
struct BrowserSearchSettingsPane: View {
    let browser: BrowserStore

    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared
    @State private var catalog: BrowserSearchCatalog
    @State private var editing: BrowserSearchProviderDraft?

    init(browser: BrowserStore) {
        self.browser = browser
        _catalog = State(initialValue: BrowserSearchCatalog(core: browser.core))
    }

    var body: some View {
        BrowserSettingsPane(.search) {
            BrowserDefaultSearchSettingsSection(
                preferences: appPreferences, catalog: catalog, profileID: browser.shownSpace?.profileID)
            BrowserPaletteResultsSettingsSection(preferences: appPreferences)
            BrowserPaletteTypingSettingsSection(preferences: appPreferences, browser: browser)
            BrowserSearchProvidersSettingsSection(
                catalog: catalog, profileID: browser.shownSpace?.profileID, editing: $editing)
        }
        .sheet(item: $editing) { draft in
            BrowserSearchProviderEditor(draft: draft, catalog: catalog, profileID: browser.shownSpace?.profileID)
        }
    }
}
