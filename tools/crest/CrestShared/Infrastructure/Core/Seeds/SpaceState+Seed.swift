import Foundation

extension SpaceState.Seed {
    // MARK: - Initializers

    /// A Space to seed a session with, with its own profile unless named.
    /// It uses balanced content blocking and keeps browsing records unless told otherwise.
    init(
        id: UUID = UUID(),
        profileID: UUID = UUID(),
        name: String,

        folders: [FolderState.Seed] = [],
        tabs: [TabState.Seed],
        archivedTabs: [ArchivedTabState.Seed] = [],
        history: [HistoryEntryState] = [],
        browsingPreferences: BrowsingPreferences = .seeded,
        isGitHubFolderDismissed: Bool = false,
        color: SpaceColor = .blue
    ) {
        self.init(
            id: id, profileID: profileID,
            settings: SpaceSettings.Seed(
                name: name,
                browsingPreferences: browsingPreferences,
                isGitHubFolderDismissed: isGitHubFolderDismissed, storedColor: color),
            folders: folders, tabs: tabs, archivedTabs: archivedTabs, history: history)
    }

    /// The `number`th blank Space of a session, counting from one: named for
    /// its number, with one Start Page.
    static func blank(number: Int) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Space \(number)",
            tabs: [.startPage()])
    }

    // MARK: - Actions - Reading

    /// The tab the seed holds open with this identity.
    func tab(id: UUID) -> TabState.Seed? {
        tabs.first { $0.id == id }
    }
}
