import Foundation

enum MobileSettingsDestinationFilter {
    /// The destinations the list shows: those `state`'s engines provide,
    /// matching `searchText`.
    @MainActor
    static func destinations(
        matching searchText: String,
        locale: Locale,
        in state: CoreState
    ) -> [BrowserSettingsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return BrowserSettingsDestination.platformCases(in: state)
        }
        return BrowserSettingsDestination.platformCases(in: state).filter {
            $0.matchesSearchQuery(query, locale: locale)
        }
    }
}
