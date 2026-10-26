/// Settings destinations whose implementations are available in the macOS shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.all

    /// The sidebar's groups of destinations, in order. Spaces list between
    /// the last two groups. Spaces, Passwords and Extensions are pages of a
    /// Space, and Feature Flags is a page of Advanced, so none has a row.
    static let groups: [[BrowserSettingsDestination]] = [
        [.general, .tabs, .search, .lookAndFeel, .links, .engines, .shortcuts, .sync, .privacy],
        [.agents, .advanced, .about],
    ]

    /// Destinations without a row, each opened from the page of the
    /// destination whose row stands for it.
    static let parents: [BrowserSettingsDestination: BrowserSettingsDestination] = [.featureFlags: .advanced]

    /// The destination whose row stands for `destination` when it has none.
    static func parent(of destination: BrowserSettingsDestination) -> BrowserSettingsDestination? {
        parents[destination]
    }
}
