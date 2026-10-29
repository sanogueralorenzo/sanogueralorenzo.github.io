import Foundation

extension SessionTabs {
    mutating func setLiveOptions(_ id: UUID, options: GitHubLiveFolderOptions) throws {
        _ = try folder(id)
        folders[folders.firstIndex { $0.id == id }!].liveOptions = options
    }
    mutating func enableLiveFolder(_ id: UUID, source: LiveFolderSource) throws {
        if folders.contains(where: { $0.source == source && $0.id != id }) {
            throw Rejection.folderAlreadyExists(FolderAlreadyExists(folderID: id))
        }
        if let folder = folders.first(where: { $0.id == id }) {
            guard folder.source == source else {
                throw Rejection.folderAlreadyExists(FolderAlreadyExists(folderID: id))
            }
            guard folder.location == .saved else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        } else {
            try addFolder(id, name: String(localized: source.title))
            folders[folders.firstIndex { $0.id == id }!].source = source
        }
    }
    mutating func refreshLiveFolder(_ id: UUID, source: LiveFolderSource, items: [TabState.Seed], at now: Date) throws {
        try enableLiveFolder(id, source: source)
        let wanted = Set(items.map { $0.savedURL.map { Data($0.utf8) } })
        let previous = tabs.filter { $0.folderID == id }
        func away(_ value: TabState.Seed) -> Bool {
            guard value.placement.isDurable, let saved = value.savedURL ?? value.url, let url = value.url else {
                return false
            }
            return !PageAddress.samePage(saved, url)
        }
        for value in previous where !wanted.contains(value.savedURL.map { Data($0.utf8) }) {
            let preserve = !Self.accepts(source, address: value.savedURL) || away(value)
            try move(value.id, to: .current, folder: nil, before: nil, detachSplit: true, at: now)
            if !preserve {
                try dismiss(
                    [value.id], selected: nil, fallback: nil, at: now, deleting: false, ensuresSelection: false,
                    resetsPlacement: true)
            }
        }
        for item in items {
            if let existing = previous.first(where: {
                $0.savedURL.map { Data($0.utf8) } == item.savedURL.map { Data($0.utf8) }
            }) {
                if !away(existing) && !item.title.isEmpty { try edit(existing.id) { $0.title = item.title } }
                continue
            }
            let value = try Self.restored(item)
            try insert(value)
            try file([value.id], at: .saved, folder: id, now: now, detachesSplitMembers: true)
        }
    }
    static func accepts(_ source: LiveFolderSource, address: String?) -> Bool {
        guard source.name == "githubPullRequests", let address, address.utf16.count <= 4096,
            let url = URL(string: address), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "github.com",
            parts.port == nil || parts.port == 443, parts.user?.isEmpty != false, parts.password == nil,
            parts.query == nil, parts.fragment == nil
        else { return false }
        let path = parts.percentEncodedPath.components(separatedBy: "/")
        guard path.count == 5, path[0].isEmpty, !path[1].isEmpty, !path[2].isEmpty, path[3] == "pull",
            let first = path[4].utf8.first, (49...57).contains(first)
        else { return false }
        return path[4].utf8.allSatisfy { (48...57).contains($0) }
    }
}
