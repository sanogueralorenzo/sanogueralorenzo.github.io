import Foundation

extension BrowsingPreferences {
    // MARK: - Variables

    /// What a seeded Space searches and keeps unless told otherwise: the
    /// device's default search and suggestions, current tabs swept after twelve
    /// hours, balanced content blocking, and everything it browses kept.
    static let seeded = BrowsingPreferences.seeded()

    // MARK: - Initializers

    /// A seeded Space's preferences that search with `engine`, or follow the
    /// device's default search for nil, sweep current tabs under `cleanup` and
    /// block content under `blocking`, keeping everything it browses.
    static func seeded(
        engine: BuiltInSearchProvider? = nil,
        cleanup: CurrentTabCleanup = .after12Hours,
        blocking: ContentBlockingPolicy = .balanced
    ) -> BrowsingPreferences {
        BrowsingPreferences(
            selectedBuiltInEngine: engine ?? .google, selectedCustomEngineID: nil, customSearchProviders: [],
            searchSuggestionsEnabled: false, followsDefaultSearch: engine == nil, followsDefaultSuggestions: true,
            currentTabCleanup: cleanup, contentBlocking: blocking,
            dataRetention: DataRetentionPreferences(history: .forever, archive: .forever, downloads: .forever))
    }
}
