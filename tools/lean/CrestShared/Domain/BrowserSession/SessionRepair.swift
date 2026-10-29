import Foundation

/// Repairs detached values before a workspace adopts them; runtime assets follow their recorded origins.
struct SessionRepair {
    struct Origin: Equatable {
        let spaceIndex: Int
        let tabIndex: Int
        let sourceSpaceID: UUID
        let sourceTabID: UUID
    }
    struct Result {
        let session: SessionState.Seed
        let origins: [Origin]
    }
    private var spaces: Set<UUID> = []
    private var profiles: Set<UUID> = []
    private var tabs: Set<UUID> = []
    private var origins: [Origin] = []
    private let now: Date
    private let ids: () -> UUID
    init(now: Date, ids: @escaping () -> UUID) {
        self.now = now
        self.ids = ids
    }

    static func empty(_ template: SpaceState.Seed? = nil, now: Date, ids: () -> UUID) -> SpaceState.Seed {
        var value =
            template
            ?? SpaceState.Seed(
                id: SessionValidation.emptyID, profileID: SessionValidation.emptyID, name: "Space 1", tabs: [])
        if template == nil { value.settings.storedColor = nil }
        value.id = ids()
        value.profileID = ids()
        value.folders = []
        value.tabs = [.startPage(id: ids(), lastActivatedAt: now)]
        value.archivedTabs = []
        value.history = []
        return value
    }
    mutating func repair(_ source: SessionState.Seed, empty template: SpaceState.Seed? = nil) throws -> Result {
        var source = source
        let pending = Set(source.spaceDeletions.map(\.spaceID))
        if source.spaces.isEmpty || source.spaces.allSatisfy({ pending.contains($0.id) }) {
            source.spaces.append(Self.empty(template, now: now, ids: ids))
        }
        var repaired: [SpaceState.Seed] = []
        for (index, space) in source.spaces.enumerated() {
            do {
                repaired.append(
                    try pending.contains(space.id) ? kept(space, index: index) : self.repaired(space, index: index))
            } catch is InvalidDeletion {
                throw Rejection.invalidSession(InvalidSession(flaw: SessionValidation.flaw(source) ?? .unreadable))
            }
        }
        source.spaces = repaired
        try SessionValidation.require(source)
        return Result(session: source, origins: origins)
    }
    private struct InvalidDeletion: Error {}
    private static func claim(_ preferred: UUID, in seen: inout Set<UUID>, ids: () -> UUID) -> UUID {
        if preferred != SessionValidation.emptyID && seen.insert(preferred).inserted { return preferred }
        while true {
            let next = ids()
            if next != SessionValidation.emptyID && seen.insert(next).inserted { return next }
        }
    }
    private mutating func kept(_ value: SpaceState.Seed, index: Int) throws -> SpaceState.Seed {
        guard Self.claim(value.id, in: &spaces, ids: ids) == value.id,
            Self.claim(value.profileID, in: &profiles, ids: ids) == value.profileID
        else {
            throw InvalidDeletion()
        }
        for (tabIndex, tab) in value.tabs.enumerated() {
            _ = Self.claim(tab.id, in: &tabs, ids: ids)
            origins.append(Origin(spaceIndex: index, tabIndex: tabIndex, sourceSpaceID: value.id, sourceTabID: tab.id))
        }
        for entry in value.archivedTabs where !SessionTabs.isStartPage(entry.tab) {
            _ = Self.claim(entry.tab.id, in: &tabs, ids: ids)
        }
        return value
    }
    private mutating func repaired(_ source: SpaceState.Seed, index: Int) throws -> SpaceState.Seed {
        var value = source
        value.id = Self.claim(source.id, in: &spaces, ids: ids)
        value.profileID = Self.claim(source.profileID, in: &profiles, ids: ids)
        var folderIDs: Set<UUID> = []
        let folders = source.folders.map { folder -> FolderState.Seed in
            var value = folder
            value.id = Self.claim(folder.id, in: &folderIDs, ids: ids)
            return value
        }
        value.folders = try SessionFolders.repairedPreorder(folders)
        let locations = Dictionary(uniqueKeysWithValues: value.folders.map { ($0.id, $0.location) })
        var counts: [TabPlacement: Int] = [:]
        var kept: [TabState.Seed] = []
        for (tabIndex, tab) in source.tabs.enumerated() {
            var value = tab
            value.id = Self.claim(tab.id, in: &tabs, ids: ids)
            origins.append(Origin(spaceIndex: index, tabIndex: tabIndex, sourceSpaceID: source.id, sourceTabID: tab.id))
            counts[tab.placement, default: 0] += 1
            if let capacity = tab.placement.capacity, counts[tab.placement]! > capacity { value.placement = .saved }
            if !value.placement.holdsFolders || value.folderID.flatMap({ locations[$0] }) != value.placement {
                value.folderID = nil
            }
            value.savedURL = value.placement.isDurable ? tab.savedURL ?? tab.url : nil
            kept.append(Self.normalized(value))
        }
        if kept.isEmpty { kept.append(.startPage(id: Self.claim(ids(), in: &tabs, ids: ids), lastActivatedAt: now)) }
        value.tabs = SessionTabs.repairedSplits(kept)
        var archive: [ArchivedTabState.Seed] = []
        for var entry in source.archivedTabs where !SessionTabs.isStartPage(entry.tab) {
            entry.tab.id = Self.claim(entry.tab.id, in: &tabs, ids: ids)
            entry.tab.placement = .current
            entry.tab.savedURL = nil
            entry.tab.folderID = nil
            entry.tab.splitGroupID = nil
            entry.tab = Self.normalized(entry.tab)
            archive.append(entry)
        }
        value.archivedTabs = archive
        value.history = Array(source.history.prefix(SessionValidation.maximumHistory))
        return value
    }
    private static func normalized(_ source: TabState.Seed) -> TabState.Seed {
        var value = source
        value.customTitle = SessionTabs.customTitle(source.customTitle)
        value.positionModifiedAt = source.positionModifiedAt.map(SessionTabs.timestamp)
        value.titleModifiedAt = source.titleModifiedAt.map(SessionTabs.timestamp)
        if SessionTabs.isStartPage(value) {
            value.title = TabState.Seed.startPageTitle
            value.symbol = TabState.Seed.startPageSymbol
        }
        return value
    }
}
