import Foundation

/// A utility list a Space shows: its archive, its history or its downloads.
/// Each surface carries its presentation, the filters it offers and the items
/// it lists. The selected surface is remembered by its name, so a name never
/// changes. Surfaces are equal when their names are.
struct BrowserUtilitySurface: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each platform presents a surface with its own view, so the one place
    /// that builds that view switches over the kind.
    enum Kind: Sendable {
        case archive
        case history
        case downloads
    }

    // MARK: - Variables

    static let archive = BrowserUtilitySurface(
        kind: .archive,
        name: "archive",
        title: "Archive",
        systemImage: "archivebox",
        searchPrompt: "Search Archive…",
        emptyTitle: "No Archived Tabs",
        emptyDescription: "Closed and automatically cleaned tabs from this Space appear here.",
        noResults: { query in "No archived tabs in this Space match “\(query)”." },
        filterLabel: "Filter Archive",
        filters: [.all] + BrowserUtilityListFilter.archive,
        items: { request in
            request.archivedTabs.filter { $0.tab.surface != .startPage }.map(BrowserUtilityListItem.archive)
        }
    )
    static let history = BrowserUtilitySurface(
        kind: .history,
        name: "history",
        title: "History",
        systemImage: "clock.arrow.circlepath",
        searchPrompt: "Search History…",
        emptyTitle: "No History",
        emptyDescription: "Completed visits from this Space appear here and remain separate from every other Space.",
        noResults: { query in "No history entries in this Space match “\(query)”." },
        filterLabel: "Filter History",
        filters: [.all] + BrowserUtilityListFilter.history,
        items: { request in request.history.map(BrowserUtilityListItem.history) },
        clearsHistory: true
    )
    static let downloads = BrowserUtilitySurface(
        kind: .downloads,
        name: "downloads",
        title: "Downloads",
        systemImage: "arrow.down.circle",
        searchPrompt: "Search Downloads…",
        emptyTitle: "No Downloads",
        emptyDescription: "Downloads from this Space appear here.",
        noResults: { query in "No downloads in this Space match “\(query)”." },
        filterLabel: "Filter Downloads",
        filters: [.all] + BrowserUtilityListFilter.downloads,
        items: { request in request.downloads.map(BrowserUtilityListItem.download) }
    )

    /// The surfaces, in the order the switcher offers them.
    static let all = [archive, history, downloads]

    let kind: Kind
    let name: String
    let title: LocalizedStringResource
    let systemImage: String
    let searchPrompt: LocalizedStringResource
    let emptyTitle: LocalizedStringResource
    let emptyDescription: LocalizedStringResource
    let filterLabel: LocalizedStringResource

    /// The filters the surface's menu offers, everything first.
    let filters: [BrowserUtilityListFilter]

    /// The filter menu also offers to clear the Space's history.
    let clearsHistory: Bool

    private let noResults: @Sendable (String) -> LocalizedStringResource
    private let items: @Sendable (BrowserUtilityListRequest) -> [BrowserUtilityListItem]

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kind,
        name: String,
        title: LocalizedStringResource,
        systemImage: String,
        searchPrompt: LocalizedStringResource,
        emptyTitle: LocalizedStringResource,
        emptyDescription: LocalizedStringResource,
        noResults: @escaping @Sendable (String) -> LocalizedStringResource,
        filterLabel: LocalizedStringResource,
        filters: [BrowserUtilityListFilter],
        items: @escaping @Sendable (BrowserUtilityListRequest) -> [BrowserUtilityListItem],
        clearsHistory: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.systemImage = systemImage
        self.searchPrompt = searchPrompt
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.noResults = noResults
        self.filterLabel = filterLabel
        self.filters = filters
        self.items = items
        self.clearsHistory = clearsHistory
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserUtilitySurface? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Presentation

    func noResultsDescription(matching query: String) -> LocalizedStringResource {
        noResults(query)
    }

    /// The items the surface lists from `request`, before search and filters.
    func items(in request: BrowserUtilityListRequest) -> [BrowserUtilityListItem] {
        items(request)
    }

    // MARK: - Actions - Equality

    static func == (lhs: BrowserUtilitySurface, rhs: BrowserUtilitySurface) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
