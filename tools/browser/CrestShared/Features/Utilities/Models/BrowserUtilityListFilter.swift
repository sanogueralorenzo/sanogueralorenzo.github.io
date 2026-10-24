import Foundation

/// A filter of a utility list. The archive's filters are the core's archive
/// filter groups, the downloads' ask what a download's phase says about
/// itself, and history's ask how recently a page was visited. Filters are
/// equal when their names are.
struct BrowserUtilityListFilter: Hashable, Identifiable, Sendable {
    // MARK: - Variables

    static let all = BrowserUtilityListFilter(
        name: "all",
        title: "All",
        systemImage: "line.3.horizontal.decrease",
        passes: { _, _, _ in true }
    )

    /// One filter for each of the core's archive filter groups, in its order.
    static let archive: [BrowserUtilityListFilter] = ArchiveFilterGroup.all.map { group in
        BrowserUtilityListFilter(
            name: "archive.\(group.name)",
            title: group.title,
            systemImage: group.symbol
        ) { item, _, _ in
            guard case .archive(let archived) = item else { return false }
            return archived.reason.filterGroup == group
        }
    }

    static let historyToday = BrowserUtilityListFilter(
        name: "history.today",
        title: "Today",
        systemImage: "calendar"
    ) { item, now, calendar in
        guard case .history(let entry) = item else { return false }
        return calendar.isDate(entry.lastVisitedAt, inSameDayAs: now)
    }
    static let historyPastWeek = visited(within: 7, .day, name: "history.pastWeek", title: "Past Week")
    static let historyPastMonth = visited(within: 1, .month, name: "history.pastMonth", title: "Past Month")
    static let history = [historyToday, historyPastWeek, historyPastMonth]

    static let downloadsInProgress = downloadPhase(
        name: "downloads.inProgress",
        title: "In Progress",
        systemImage: "arrow.down.circle"
    ) { $0.isLive }
    static let downloadsFinished = downloadPhase(
        name: "downloads.finished",
        title: "Finished",
        systemImage: "checkmark.circle.fill"
    ) { $0.isComplete }
    static let downloadsNeedsAttention = downloadPhase(
        name: "downloads.needsAttention",
        title: "Needs Attention",
        systemImage: "exclamationmark.triangle.fill"
    ) { $0.needsAttention }
    static let downloads = [downloadsInProgress, downloadsFinished, downloadsNeedsAttention]

    let name: String
    let title: LocalizedStringResource
    let systemImage: String
    private let passes: @Sendable (BrowserUtilityListItem, Date, Calendar) -> Bool
    private let expiry: (@Sendable (BrowserUtilityListItem, Calendar) -> Date?)?

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String,
        title: LocalizedStringResource,
        systemImage: String,
        expiry: (@Sendable (BrowserUtilityListItem, Calendar) -> Date?)? = nil,
        passes: @escaping @Sendable (BrowserUtilityListItem, Date, Calendar) -> Bool
    ) {
        self.name = name
        self.title = title
        self.systemImage = systemImage
        self.expiry = expiry
        self.passes = passes
    }

    /// History visited within the last `count` units.
    private static func visited(
        within count: Int,
        _ unit: Calendar.Component,
        name: String,
        title: LocalizedStringResource
    ) -> BrowserUtilityListFilter {
        BrowserUtilityListFilter(
            name: name,
            title: title,
            systemImage: "calendar.badge.clock",
            expiry: { item, calendar in
                guard case .history(let entry) = item else { return nil }
                return calendar.date(byAdding: unit, value: count, to: entry.lastVisitedAt)
            },
            passes: { item, now, calendar in
                guard case .history(let entry) = item else { return false }
                return entry.lastVisitedAt >= calendar.date(byAdding: unit, value: -count, to: now) ?? .distantPast
            }
        )
    }

    /// Downloads whose phase passes `phase`.
    private static func downloadPhase(
        name: String,
        title: LocalizedStringResource,
        systemImage: String,
        phase: @escaping @Sendable (DownloadPhase) -> Bool
    ) -> BrowserUtilityListFilter {
        BrowserUtilityListFilter(name: name, title: title, systemImage: systemImage) { item, _, _ in
            guard case .download(let download) = item else { return false }
            return phase(download.phase)
        }
    }

    // MARK: - Actions - Filtering

    /// Whether the list shows `item` at `now`.
    func includes(_ item: BrowserUtilityListItem, at now: Date, in calendar: Calendar) -> Bool {
        passes(item, now, calendar)
    }

    /// When `item` leaves the filter by growing older, or nil when age never
    /// removes it.
    func expiry(of item: BrowserUtilityListItem, in calendar: Calendar) -> Date? {
        expiry?(item, calendar)
    }

    /// This filter when `surface` offers it, and otherwise the filter that shows everything.
    func normalized(for surface: BrowserUtilitySurface) -> Self {
        surface.filters.contains(self) ? self : .all
    }

    // MARK: - Actions - Equality

    static func == (lhs: BrowserUtilityListFilter, rhs: BrowserUtilityListFilter) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
