import Foundation

extension BrowserStore {
    /// Reconciles results without replacing tab identities, renames, or personal navigation.
    func reconcileGitHub(
        _ items: [BrowserGitHubPullRequest], folderID: UUID, in spaceID: UUID, options: GitHubLiveFolderOptions
    ) async {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }), !session.spaces[index].isPrivate,
            let folder = session.spaces[index].folders.first(where: { $0.id == folderID && $0.kind == .github }),
            folder.githubOptions == options, !session.spaces[index].githubDismissed
        else { return }
        let dismissed = Set(
            session.archive.filter { $0.spaceID == spaceID && $0.wasDeletedFromLiveFolder == true }.compactMap {
                $0.tab.savedURL ?? $0.tab.url
            })
        let wanted = items.filter { !dismissed.contains($0.url) }
        let urls = Set(wanted.map(\.url))
        let previous = session.spaces[index].tabs.filter { $0.folderID == folderID }
        for tab in previous where !urls.contains(tab.savedURL ?? tab.url ?? URL(string: "about:blank")!) {
            let away = !BrowserURLs.same(tab.url, tab.savedURL)
            // A result that became personal work leaves the managed folder.
            if away || pages[tab.id]?.isProtectedFromUnloading == true {
                placeTab(tab.id, as: .current)
            } else {
                placeTab(tab.id, as: .current)
                deleteTab(tab.id, liveFolderRefresh: true)
            }
        }
        guard let current = session.spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        for item in wanted {
            if let position = session.spaces[current].tabs.firstIndex(where: {
                $0.folderID == folderID && $0.savedURL == item.url
            }) {
                if BrowserURLs.same(session.spaces[current].tabs[position].url, item.url) {
                    session.spaces[current].tabs[position].title = item.title
                }
            } else {
                var tab = BrowserTab()
                tab.title = item.title
                tab.url = item.url
                tab.savedURL = item.url
                tab.placement = .saved
                tab.folderID = folderID
                tab.zoom = preferences.defaultPageZoom ?? 1
                session.spaces[current].tabs.append(tab)
            }
        }
        changed()
    }
}
