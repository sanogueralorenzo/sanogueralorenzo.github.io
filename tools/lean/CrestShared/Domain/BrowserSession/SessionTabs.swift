import Foundation

/// The editable value of one Space's tabs and folders. No page or window lives here.
struct SessionTabs {
    static let maximumTabs = 5000
    static let maximumNameLength = 200
    static let maximumSplitMembers = 4
    var tabs: [TabState.Seed]
    var folders: [FolderState.Seed]
    private(set) var archived: [ArchivedTabState.Seed] = []

    init(tabs: [TabState.Seed], folders: [FolderState.Seed]) throws {
        self.tabs = try tabs.map(Self.restored)
        self.folders = folders
        try SessionFolders(folders).validate()
        repairSplits()
    }
    init(_ space: SpaceState.Seed) throws { try self.init(tabs: space.tabs, folders: space.folders) }
    func capture(_ source: SpaceState.Seed) -> SpaceState.Seed {
        var value = source
        value.tabs = tabs
        value.folders = folders
        value.archivedTabs += archived
        return value
    }
    func tab(_ id: UUID) throws -> TabState.Seed {
        guard let value = tabs.first(where: { $0.id == id }) else { throw Rejection.unknownTab(UnknownTab(tabID: id)) }
        return value
    }
    func folder(_ id: UUID) throws -> FolderState.Seed { try SessionFolders(folders).folder(id) }
    mutating func edit(_ id: UUID, _ action: (inout TabState.Seed) throws -> Void) throws {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            throw Rejection.unknownTab(UnknownTab(tabID: id))
        }
        try action(&tabs[index])
    }
    static func isStartPage(_ tab: TabState.Seed) -> Bool { tab.nativeContent == nil && tab.url == nil }
    static func timestamp(_ now: Date) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 * 1000).rounded(.toNearestOrAwayFromZero) / 1000)
    }
    static func customTitle(_ title: String?) -> String? {
        title.map(BrowserAddress.trimmed).flatMap { $0.isEmpty ? nil : $0 }
    }
    static func restored(_ source: TabState.Seed) throws -> TabState.Seed {
        var tab = source
        tab.customTitle = customTitle(source.customTitle)
        if let native = tab.nativeContent, BrowserAddress.trimmed(native.kind).isEmpty || tab.url != nil {
            throw Rejection.invalidTabContent(InvalidTabContent(tabID: tab.id))
        }
        return tab
    }
    static func place(
        _ tab: inout TabState.Seed, at placement: TabPlacement, folder: UUID?, now: Date? = nil,
        preservesSplit: Bool = false
    ) {
        guard tab.placement != placement || tab.folderID != folder else { return }
        tab.savedURL = placement.isDurable ? tab.savedURL ?? tab.url : nil
        tab.placement = placement
        tab.folderID = folder
        if !preservesSplit { tab.splitGroupID = nil }
        if let now { tab.positionModifiedAt = timestamp(now) }
    }
    mutating func rename(_ id: UUID, title: String?, at now: Date) throws {
        let name = Self.customTitle(title)
        try edit(id) {
            guard $0.customTitle.map({ Data($0.utf8) }) != name.map({ Data($0.utf8) }) else { return }
            guard name?.utf16.count ?? 0 <= 4096 else { throw Rejection.invalidName(InvalidName(limit: 4096)) }
            $0.customTitle = name
            $0.titleModifiedAt = Self.timestamp(now)
        }
    }
    static func requireRoom(_ placement: TabPlacement, count: Int) throws {
        if let capacity = placement.capacity, count > capacity {
            throw Rejection.pinnedTabsFull(PinnedTabsFull(capacity: capacity))
        }
    }
    func nextSection(_ values: [TabState.Seed], _ placement: TabPlacement) -> Int {
        values.firstIndex { $0.placement.rank > placement.rank } ?? values.count
    }
    func splitMembers(_ id: UUID) throws -> [TabState.Seed] {
        let value = try tab(id)
        guard let group = value.splitGroupID else { return [value] }
        let index = tabs.firstIndex { $0.id == id }!
        var first = index
        var last = index
        while first > 0 && tabs[first - 1].splitGroupID == group { first -= 1 }
        while last + 1 < tabs.count && tabs[last + 1].splitGroupID == group { last += 1 }
        return Array(tabs[first...last])
    }
    func insertionAfter(_ id: UUID) throws -> Int? {
        guard tabs.contains(where: { $0.id == id }) else { return nil }
        let last = try splitMembers(id).last!.id
        return tabs.firstIndex { $0.id == last }! + 1
    }
    mutating func insert(_ tab: TabState.Seed, at requested: Int? = nil, duplicate: Bool = false) throws {
        try Self.requireRoom(tab.placement, count: tabs.filter { $0.placement == tab.placement }.count + 1)
        guard tabs.count < Self.maximumTabs else {
            throw Rejection.tabLimitReached(TabLimitReached(limit: Self.maximumTabs))
        }
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: tab.id))
        }
        let lower = tabs.firstIndex { $0.placement.rank >= tab.placement.rank } ?? tabs.count
        let upper = nextSection(tabs, tab.placement)
        let insertion =
            requested.map { min(max($0, lower), upper) } ?? (duplicate || !tab.placement.isDurable ? lower : upper)
        tabs.insert(tab, at: insertion)
    }
    @discardableResult
    mutating func move(
        _ id: UUID, to placement: TabPlacement, folder: UUID?, before: UUID?, detachSplit: Bool, at now: Date
    ) throws -> Bool {
        var value = try tab(id)
        guard before != id else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        if let folder, try self.folder(folder).location != placement || !placement.holdsFolders {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        var remaining = tabs.filter { $0.id != id }
        try Self.requireRoom(placement, count: remaining.filter { $0.placement == placement }.count + 1)
        func matches(_ tab: TabState.Seed) -> Bool { tab.placement == placement && tab.folderID == folder }
        let insertion =
            before.flatMap { anchor in remaining.firstIndex { $0.id == anchor && matches($0) } }
            ?? remaining.lastIndex(where: matches).map { $0 + 1 } ?? nextSection(remaining, placement)
        if tabs.firstIndex(where: { $0.id == id }) == insertion && value.placement == placement
            && value.folderID == folder
            && (!detachSplit || value.splitGroupID == nil)
        {
            return false
        }
        let ordered = try SessionFolders(folders).preservingOrder(removing: [id], tabs: tabs)
        Self.place(&value, at: placement, folder: folder, now: now, preservesSplit: !detachSplit)
        if detachSplit { value.splitGroupID = nil }
        value.positionModifiedAt = Self.timestamp(now)
        remaining.insert(value, at: insertion)
        tabs = remaining
        folders = ordered
        repairSplits()
        if detachSplit { normalizeSplits(at: now) }
        return true
    }
    @discardableResult
    mutating func dismiss(
        _ requested: [UUID], selected: UUID?, fallback: UUID?, at now: Date, deleting: Bool, ensuresSelection: Bool,
        resetsPlacement: Bool
    ) throws -> UUID? {
        let removing = Set(requested)
        for id in removing { _ = try tab(id) }
        let removed = tabs.filter { removing.contains($0.id) }
        if !deleting, let durable = removed.first(where: { $0.placement.isDurable }) {
            throw Rejection.currentTabsOnly(CurrentTabsOnly(tabID: durable.id))
        }
        let ordered = try SessionFolders(folders).preservingOrder(removing: removing, tabs: tabs)
        for var value in removed where !Self.isStartPage(value) {
            value.splitGroupID = nil
            if resetsPlacement {
                value.placement = .current
                value.folderID = nil
                value.savedURL = nil
            }
            archived.append(ArchivedTabState.Seed(tab: value, archivedAt: now, reason: deleting ? .deleted : .closed))
        }
        tabs.removeAll { removing.contains($0.id) }
        folders = ordered
        var selected = selected
        if let current = selected, removing.contains(current) {
            selected = tabs.contains { $0.id == fallback } ? fallback : nil
        }
        if ensuresSelection && !tabs.contains(where: { $0.id == selected }) { selected = fallbackSelection() }
        normalizeSplits(at: now)
        return selected
    }
    private func fallbackSelection() -> UUID? {
        tabs.min { $0.placement.fallbackRank < $1.placement.fallbackRank }?.id
    }
    mutating func restore(_ source: TabState.Seed, at now: Date) throws -> TabState.Seed {
        var value = source
        value.placement = .current
        value.folderID = nil
        value.splitGroupID = nil
        value.lastActivatedAt = now
        value.positionModifiedAt = Self.timestamp(now)
        value.customTitle = Self.customTitle(source.customTitle)
        value = try Self.restored(value)
        try insert(value)
        return value
    }
    mutating func repairSplits() {
        var retired: Set<UUID> = []
        var run: UUID?
        var placement: TabPlacement?
        var folder: UUID?
        var length = 0
        for index in tabs.indices {
            let value = tabs[index]
            tabs[index].splitGroupID = nil
            guard let group = value.splitGroupID, value.placement.holdsSplits else {
                if let run { retired.insert(run) }
                run = nil
                length = 0
                continue
            }
            if run != group {
                if let run { retired.insert(run) }
                run = nil
                length = 0
                if retired.contains(group) { continue }
                run = group
                placement = value.placement
                folder = value.folderID
                length = 1
            } else {
                if value.placement != placement || value.folderID != folder {
                    retired.insert(group)
                    run = nil
                    length = 0
                    continue
                }
                if length >= Self.maximumSplitMembers { continue }
                length += 1
            }
            tabs[index].splitGroupID = group
        }
    }
    mutating func normalizeSplits(at now: Date) {
        repairSplits()
        let counts = Dictionary(tabs.compactMap(\.splitGroupID).map { ($0, 1) }, uniquingKeysWith: +)
        for index in tabs.indices {
            if let group = tabs[index].splitGroupID, counts[group]! < 2 {
                tabs[index].splitGroupID = nil
                tabs[index].positionModifiedAt = Self.timestamp(now)
            }
        }
    }
}
