import Foundation

extension GitHubLiveFolderOptions {
    var isValid: Bool {
        excludedRepositories.count <= 100
            && excludedRepositories.allSatisfy { repository in
                let parts = BrowserAddress.trimmed(repository).split(separator: "/", omittingEmptySubsequences: false)
                return repository.utf16.count <= 256 && parts.count == 2
                    && parts.allSatisfy {
                        !$0.isEmpty
                            && $0.utf8.allSatisfy {
                                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                                    || [95, 46, 45].contains($0)
                            }
                    }
            }
    }
    var normalized: Self {
        var seen: Set<String> = []
        var value = self
        value.excludedRepositories = excludedRepositories.map(BrowserAddress.trimmed).filter {
            seen.insert($0.lowercased()).inserted
        }.sorted { $0.lowercased() < $1.lowercased() }
        return value
    }
    func matches(_ other: Self) -> Bool {
        authorMe == other.authorMe && assignedMe == other.assignedMe && reviewRequested == other.reviewRequested
            && includeDrafts == other.includeDrafts && interval == other.interval
            && excludedRepositories.map { $0.lowercased() } == other.excludedRepositories.map { $0.lowercased() }
    }
}

extension SessionMutations {
    func liveFolder(_ request: some SessionIntent) throws -> SessionMutation? {
        switch request {
        case let request as EnableGitHubLiveFolder:
            try requirePreferences()
            let original = try space(request.spaceID)
            guard original.profileID == request.profileID else {
                throw Rejection.invalidLiveFolder(InvalidLiveFolder(spaceID: original.id))
            }
            let existing = original.folders.first { $0.source == .gitHubPullRequests }
            var values = try SessionTabs(original)
            try values.enableLiveFolder(existing?.id ?? request.folderID, source: .gitHubPullRequests)
            var next = values.capture(original)
            if original.settings.isGitHubFolderDismissed {
                for index in next.archivedTabs.indices
                where next.archivedTabs[index].reason == .deleted
                    && SessionTabs.accepts(
                        .gitHubPullRequests,
                        address: next.archivedTabs[index].tab.savedURL ?? next.archivedTabs[index].tab.url)
                { next.archivedTabs[index].reason = .closed }
            }
            next.settings.isGitHubFolderDismissed = false
            return replacing([next], stage: .creation)
        case let request as SetGitHubLiveFolderOptions:
            try requirePreferences()
            let original = try space(request.spaceID)
            guard original.profileID == request.profileID, request.options.isValid,
                original.folders.first(where: { $0.id == request.folderID })?.source == .gitHubPullRequests
            else { throw Rejection.invalidLiveFolder(InvalidLiveFolder(spaceID: original.id)) }
            return try organizing(original.id) {
                try $0.setLiveOptions(request.folderID, options: request.options.normalized)
            }
        case let request as RefreshLiveFolder:
            try requirePreferences()
            let original = try space(request.spaceID)
            guard !original.settings.isGitHubFolderDismissed, original.profileID == request.profileID,
                request.tabs.count <= 100,
                request.tabs.allSatisfy({
                    SessionTabs.accepts(request.source, address: $0.url) && !BrowserAddress.trimmed($0.title).isEmpty
                        && $0.title.utf16.count <= 512
                })
            else { throw Rejection.invalidLiveFolder(InvalidLiveFolder(spaceID: original.id)) }
            let options = request.expectedOptions ?? .default
            let current = original.folders.first { $0.id == request.folderID }?.liveOptions ?? .default
            guard options.isValid, current.matches(options.normalized) else {
                throw Rejection.invalidLiveFolder(InvalidLiveFolder(spaceID: original.id))
            }
            let dismissed = Set(
                original.archivedTabs.filter { $0.reason == .deleted }.compactMap {
                    ($0.tab.savedURL ?? $0.tab.url).map { Data($0.utf8) }
                })
            var seen: Set<Data> = []
            let items = try request.tabs.filter {
                seen.insert(Data($0.url.utf8)).inserted && !dismissed.contains(Data($0.url.utf8))
            }.map {
                try newTab(ids(), content: TabContent(address: $0.url, view: nil, title: $0.title), placement: .saved)
            }
            return try organizing(original.id, stage: .creation) {
                try $0.refreshLiveFolder(request.folderID, source: request.source, items: items, at: now)
            }
        default: return nil
        }
    }
}
