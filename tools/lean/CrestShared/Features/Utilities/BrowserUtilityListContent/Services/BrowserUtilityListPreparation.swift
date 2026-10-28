import Foundation

enum BrowserUtilityListPreparation {
    static let searchDebounce = Duration.milliseconds(60)

    nonisolated static func nextRefreshDate(
        for request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let itemDates = baseItems(for: request).map(\.date)
        guard !itemDates.isEmpty else { return nil }

        var deadlines: [Date] = []
        let startOfToday = calendar.startOfDay(for: now)
        if let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) {
            deadlines.append(nextDay)
        }

        let activeFilter = request.filter.normalized(for: request.surface)
        deadlines += baseItems(for: request).compactMap { activeFilter.expiry(of: $0, in: calendar) }

        return deadlines.filter { $0 > now }.min()
    }

    nonisolated static func sections(
        for request: BrowserUtilityListRequest,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BrowserUtilityListSection] {
        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [BrowserUtilityListItem] = []
        for item in baseItems(for: request) {
            guard !Task.isCancelled else { return [] }
            guard item.matches(query),
                matchesFilter(
                    item,
                    request: request,
                    now: now,
                    calendar: calendar
                )
            else { continue }
            items.append(item)
        }
        guard !Task.isCancelled else { return [] }
        items.sort { $0.date > $1.date }
        guard !Task.isCancelled else { return [] }

        var timeframes: [BrowserUtilityTimeSection] = []
        var grouped: [BrowserUtilityTimeSection: [BrowserUtilityListItem]] = [:]
        for item in items {
            guard !Task.isCancelled else { return [] }
            let timeframe = BrowserUtilityTimeSection(
                date: item.date,
                now: now,
                calendar: calendar
            )
            if grouped[timeframe] == nil {
                timeframes.append(timeframe)
            }
            grouped[timeframe, default: []].append(item)
        }
        return timeframes.map { timeframe in
            BrowserUtilityListSection(
                timeframe: timeframe,
                items: grouped[timeframe, default: []]
            )
        }
    }

    nonisolated private static func baseItems(
        for request: BrowserUtilityListRequest
    ) -> [BrowserUtilityListItem] {
        request.surface.items(in: request)
    }

    nonisolated private static func matchesFilter(
        _ item: BrowserUtilityListItem,
        request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        request.filter.normalized(for: request.surface).includes(item, at: now, in: calendar)
    }
}
