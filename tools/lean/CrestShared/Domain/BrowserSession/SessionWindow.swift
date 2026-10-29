import Foundation

/// Selection, recent tabs and split proportions for one window; no native views are retained.
struct SessionWindow {
    struct Record: Equatable {
        let id: UUID
        let shownSpaceID: UUID
        let tabs: [ShownTab]
        let shares: [SplitColumnShares]
        let used: Int64
    }
    struct Place: Hashable {
        let space: UUID
        let tab: UUID
    }
    let id: UUID
    let workspaceID: UUID
    let saved: Bool
    private(set) var shownSpaceID: UUID
    private var tabs: [UUID: UUID?]
    private var shares: [UUID: [Double]]
    private var recent: [UUID: [UUID]] = [:]
    private var unseen: Set<Place> = []
    private var departed: Set<Place> = []

    private init(id: UUID, workspaceID: UUID, saved: Bool, shown: UUID, tabs: [UUID: UUID?], shares: [UUID: [Double]]) {
        self.id = id
        self.workspaceID = workspaceID
        self.saved = saved
        shownSpaceID = shown
        self.tabs = tabs
        self.shares = shares
    }
    init(restoring record: Record, workspaceID: UUID) {
        self.init(
            id: record.id, workspaceID: workspaceID, saved: true, shown: record.shownSpaceID,
            tabs: Dictionary(uniqueKeysWithValues: record.tabs.map { ($0.spaceID, $0.tabID) }),
            shares: Dictionary(uniqueKeysWithValues: record.shares.map { ($0.groupID, $0.shares) }))
    }
    init(copying other: SessionWindow, id: UUID, saved: Bool) {
        self.init(
            id: id, workspaceID: other.workspaceID, saved: saved, shown: other.shownSpaceID, tabs: other.tabs,
            shares: [:])
    }
    init(id: UUID, workspaceID: UUID, saved: Bool, session: SessionState.Seed, legacyTabs: [UUID: UUID] = [:]) {
        let available = Self.showable(session)
        let launch = available.first
        let known = legacyTabs.filter { pair in
            session.spaces.contains { $0.id == pair.key && Self.contains($0, pair.value) }
        }
        self.init(
            id: id, workspaceID: workspaceID, saved: saved,
            shown: launch?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            tabs: known.mapValues { Optional($0) }, shares: [:])
        if let launch { showSpace(launch) }
    }
    func tab(in space: UUID) -> UUID? { tabs[space] ?? nil }
    var shownTabs: [ShownTab] { tabs.map { ShownTab(spaceID: $0.key, tabID: $0.value) } }
    static func fallbackTab(_ space: SpaceState.Seed) -> UUID? {
        space.tabs.min { $0.placement.fallbackRank < $1.placement.fallbackRank }?.id
    }
    static func showable(_ session: SessionState.Seed) -> [SpaceState.Seed] {
        let deleting = Set(session.spaceDeletions.map(\.spaceID))
        return session.spaces.filter { !deleting.contains($0.id) }
    }
    private static func contains(_ space: SpaceState.Seed, _ tab: UUID?) -> Bool {
        space.tabs.contains { $0.id == tab }
    }
    static func cards(_ space: SpaceState.Seed, tab: UUID) -> ShownCards {
        let sidebar = SessionSidebar(tabs: space.tabs, folders: space.folders)
        for list in sidebar.outline.lists {
            if let row = list.rows.first(where: { $0.kind.groupsTabs && $0.members.contains(tab) }) {
                return ShownCards(spaceID: space.id, tabIDs: row.members, splitGroupID: row.id)
            }
        }
        return ShownCards(spaceID: space.id, tabIDs: [tab], splitGroupID: nil)
    }
    func state(over session: SessionState.Seed) -> WindowState {
        let cards = session.spaces.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { space -> ShownCards? in
            guard let tab = tab(in: space.id), Self.contains(space, tab) else { return nil }
            return Self.cards(space, tab: tab)
        }
        return WindowState(
            id: id, workspaceID: workspaceID, shownSpaceID: shownSpaceID,
            shownTabs: shownTabs.sorted { $0.spaceID.uuidString < $1.spaceID.uuidString },
            splitColumnShares: shares.keys.sorted { $0.uuidString < $1.uuidString }.map {
                SplitColumnShares(groupID: $0, shares: shares[$0]!)
            }, cards: cards)
    }
    func onScreen(in session: SessionState.Seed) -> [UUID] {
        guard let space = session.spaces.first(where: { $0.id == shownSpaceID }), let tab = tab(in: space.id),
            Self.contains(space, tab)
        else { return [] }
        return Self.cards(space, tab: tab).tabIDs
    }
    func recentItems(in space: SpaceState.Seed) -> [RecentTabItem] {
        guard let shown = tab(in: space.id), Self.contains(space, shown) else { return [] }
        var items = [RecentTabItem(tabIDs: Self.cards(space, tab: shown).tabIDs, focusedTabID: shown)]
        for id in (recent[space.id] ?? []).reversed() {
            if items.count == 5 { break }
            guard let value = space.tabs.first(where: { $0.id == id }), !SessionTabs.isStartPage(value),
                !unseen.contains(Place(space: space.id, tab: id)), !departed.contains(Place(space: space.id, tab: id)),
                !items.contains(where: { $0.tabIDs.contains(id) })
            else { continue }
            items.append(RecentTabItem(tabIDs: Self.cards(space, tab: id).tabIDs, focusedTabID: id))
        }
        return items
    }
    func lastUsed(in space: SpaceState.Seed, elsewhere: Set<UUID>) -> RecentTabItem? {
        guard let shown = tab(in: space.id) else { return nil }
        let showing = Set(Self.cards(space, tab: shown).tabIDs)
        var last: TabState.Seed?
        for value in space.tabs {
            guard !SessionTabs.isStartPage(value), !showing.contains(value.id),
                !departed.contains(Place(space: space.id, tab: value.id)),
                !Self.cards(space, tab: value.id).tabIDs.contains(where: elsewhere.contains)
            else { continue }
            if last == nil || value.lastActivatedAt > last!.lastActivatedAt { last = value }
        }
        return last.map { RecentTabItem(tabIDs: Self.cards(space, tab: $0.id).tabIDs, focusedTabID: $0.id) }
    }
    mutating func showSpace(_ space: SpaceState.Seed) {
        shownSpaceID = space.id
        if !Self.contains(space, tab(in: space.id)) { tabs.updateValue(Self.fallbackTab(space), forKey: space.id) }
        remember(space.id)
    }
    mutating func move(to space: UUID) { shownSpaceID = space }
    mutating func forgetTabs() {
        tabs.removeAll()
        shares.removeAll()
        recent.removeAll()
        unseen.removeAll()
        departed.removeAll()
    }
    mutating func showTab(_ tab: UUID?, in space: UUID, moves: Bool) {
        if moves && tab != nil { shownSpaceID = space }
        tabs.updateValue(tab, forKey: space)
        if let tab { departed.remove(Place(space: space, tab: tab)) }
        remember(space)
    }
    mutating func adopt(_ tab: UUID?, in space: UUID) {
        unseen.formUnion((recent[space] ?? []).map { Place(space: space, tab: $0) })
        showTab(tab, in: space, moves: false)
    }
    mutating func depart(_ tab: UUID, in space: UUID) {
        recent[space]?.removeAll { $0 == tab }
        departed.insert(Place(space: space, tab: tab))
    }
    mutating func apply(space: UUID?, tabs shown: [ShownTab], dismissed: [Place]) {
        for value in dismissed { recent[value.space]?.removeAll { $0 == value.tab } }
        for value in shown { showTab(value.tabID, in: value.spaceID, moves: false) }
        if let space { shownSpaceID = space }
    }
    mutating func dismissalFallback(in space: UUID, dismissing tab: UUID, available: Set<UUID>) -> UUID? {
        guard var history = recent[space] else { return nil }
        history.removeAll { $0 == tab }
        let fallback = history.last.flatMap { available.contains($0) ? $0 : nil }
        recent[space] = fallback == nil ? [] : history
        return fallback
    }
    mutating func repair(over session: SessionState.Seed) {
        let spaces = Dictionary(uniqueKeysWithValues: session.spaces.map { ($0.id, $0) })
        for id in Array(tabs.keys) {
            guard let space = spaces[id] else {
                tabs[id] = nil
                continue
            }
            if let tab = tab(in: id), !Self.contains(space, tab) { tabs.updateValue(nil, forKey: id) }
        }
        let available = Self.showable(session)
        if !available.contains(where: { $0.id == shownSpaceID }), let fallback = available.first { showSpace(fallback) }
        for group in Array(shares.keys) {
            if !session.spaces.contains(where: { Self.renderedColumns(in: $0, group: group) == shares[group]!.count }) {
                shares[group] = nil
            }
        }
        for id in Array(recent.keys) {
            guard let space = spaces[id] else {
                recent[id] = nil
                continue
            }
            recent[id]?.removeAll { !Self.contains(space, $0) }
        }
        for id in tabs.keys { remember(id) }
    }
    private static func renderedColumns(in space: SpaceState.Seed, group: UUID) -> Int {
        guard let start = space.tabs.firstIndex(where: { $0.splitGroupID == group }) else { return 0 }
        let count = space.tabs.dropFirst(start).prefix { $0.splitGroupID == group }.count
        return count >= SidebarOutline.minimumSplitMembers ? count : 0
    }
    @discardableResult
    mutating func resize(_ group: UUID, shares requested: [Double]) -> Bool {
        guard let normalized = Self.splitShares(requested) else { return false }
        shares[group] = normalized
        return true
    }
    static func splitShares(_ requested: [Double]) -> [Double]? {
        guard (1...SessionTabs.maximumSplitMembers).contains(requested.count),
            requested.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 })
        else { return nil }
        let total = requested.reduce(0, +)
        return abs(total - 1) <= 0.0001 ? requested : requested.map { $0 / total }
    }
    func record(used: Int64) -> Record {
        Record(
            id: id, shownSpaceID: shownSpaceID, tabs: shownTabs,
            shares: shares.map { SplitColumnShares(groupID: $0.key, shares: $0.value) }, used: used)
    }
    private mutating func remember(_ space: UUID) {
        guard let tab = tab(in: space) else { return }
        unseen.remove(Place(space: space, tab: tab))
        if recent[space]?.last == tab { return }
        recent[space, default: []].removeAll { $0 == tab }
        recent[space, default: []].append(tab)
    }
}
