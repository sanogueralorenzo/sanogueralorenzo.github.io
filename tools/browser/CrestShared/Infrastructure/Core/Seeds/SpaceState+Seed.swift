import Foundation

extension SpaceState.Seed {
    // MARK: - Initializers

    /// A Space to seed a session with, with its own profile unless named.
    /// Without `branding` it wears its accent's legacy look. It searches with
    /// Google, sweeps current tabs after twelve hours, blocks content in the
    /// balanced way and keeps what it browses, unless told otherwise.
    init(
        id: UUID = UUID(),
        profileID: UUID = UUID(),
        name: String,
        symbol: String = "square.grid.2x2.fill",
        accent: SpaceAccent = .indigo,
        branding: SpaceBranding? = nil,
        folders: [FolderState.Seed] = [],
        tabs: [TabState.Seed],
        splitGroups: [SplitGroupState.Seed] = [],
        archivedTabs: [ArchivedTabState.Seed] = [],
        history: [HistoryEntryState] = [],
        browsingPreferences: BrowsingPreferences = .seeded,
        credentialPreferences: CredentialPreferences = .seeded,
        accessPolicy: SpaceAccessPolicy = .open,
        isSavedTabsExpanded: Bool = true,
        savedTabsExpansionModifiedAt: Date? = nil
    ) {
        self.init(
            id: id, profileID: profileID,
            settings: SpaceSettings.Seed(
                name: name, symbol: symbol, accent: accent, branding: branding,
                browsingPreferences: browsingPreferences,
                credentialPreferences: credentialPreferences, accessPolicy: accessPolicy,
                isSavedTabsExpanded: isSavedTabsExpanded, savedTabsExpansionModifiedAt: savedTabsExpansionModifiedAt),
            folders: folders, tabs: tabs, splitGroups: splitGroups, archivedTabs: archivedTabs, history: history)
    }

    /// The `number`th blank Space of a session, counting from one: named for
    /// its number, wearing the next accent in turn, with one Start Page.
    static func blank(number: Int) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Space \(number)", accent: SpaceAccent.all[(number - 1) % SpaceAccent.all.count],
            tabs: [.startPage()])
    }

    // MARK: - Actions - Drafting

    /// This Space as a draft shows it before it is saved: named `name` and
    /// wearing `branding` and `symbol`.
    func wearing(_ branding: SpaceBranding, symbol: String, name: String) -> SpaceState.Seed {
        var draft = self
        draft.settings.branding = branding
        draft.settings.symbol = symbol
        draft.settings.name = name
        return draft
    }

    // MARK: - Actions - Reading

    /// The tab the seed holds open with this identity.
    func tab(id: UUID) -> TabState.Seed? {
        tabs.first { $0.id == id }
    }
}
