import Foundation

struct BrowserSettingsNavigationState: Equatable {
    var selection: BrowserSettingsSidebarItem
    var searchText: String

    init(
        selection: BrowserSettingsSidebarItem = .destination(.general),
        searchText: String = ""
    ) {
        self.selection = selection
        self.searchText = searchText
    }

    /// The destination the selection shows, or nil for a Space's page.
    var destination: BrowserSettingsDestination? {
        if case .destination(let destination) = selection { destination } else { nil }
    }

    var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The destinations the sidebar lists: those `state`'s engines provide,
    /// matching the search. A match inside a page that lives under another
    /// lists the page it lives under.
    @MainActor
    func visibleDestinations(locale: Locale, in state: CoreState) -> [BrowserSettingsDestination] {
        let provided = BrowserSettingsDestination.platformCases(in: state)
        guard !query.isEmpty else { return provided }
        let matches = provided.filter { $0.matchesSearchQuery(query, locale: locale) }
        return provided.filter { destination in
            matches.contains(destination)
                || matches.contains { BrowserPlatformSettingsDestinationCatalog.parent(of: $0) == destination }
        }
    }

    /// The page of every Space whose words the search matches, if any.
    @MainActor
    func matchingSpaceTab(locale: Locale, in state: CoreState) -> BrowserSpaceSettingsTab? {
        guard !query.isEmpty else { return nil }
        return BrowserSpaceSettingsTab.matching(query, locale: locale, in: state)
    }

    /// Whether the sidebar lists `space`: no search, a search for its name,
    /// or one for words on its pages (`spaceTab`).
    @MainActor
    func lists(_ space: SpaceModel, spaceTab: BrowserSpaceSettingsTab?) -> Bool {
        query.isEmpty || spaceTab != nil || space.settings.name.localizedStandardContains(query)
    }
}
