import Foundation

struct BrowserUtilityListClock: Sendable {
    let refreshesOverTime: Bool
    private let date: @Sendable () -> Date

    init(
        refreshesOverTime: Bool,
        date: @escaping @Sendable () -> Date
    ) {
        self.refreshesOverTime = refreshesOverTime
        self.date = date
    }

    func currentDate() -> Date {
        date()
    }

    static let live = BrowserUtilityListClock(
        refreshesOverTime: true,
        date: Date.init
    )

    static func fixed(_ date: Date) -> BrowserUtilityListClock {
        BrowserUtilityListClock(
            refreshesOverTime: false,
            date: { date }
        )
    }
}
