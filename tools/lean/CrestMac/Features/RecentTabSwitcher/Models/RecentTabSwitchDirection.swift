/// Which way a Most Recent Tab command starts through the recent tabs: the
/// forward one lands on the tab used just before this one, the backward one
/// on the tab used longest ago.
struct RecentTabSwitchDirection: Equatable, Sendable {
    // MARK: - Static Variables

    static let forward = RecentTabSwitchDirection(step: 1, startsAtOldest: false)
    static let backward = RecentTabSwitchDirection(step: -1, startsAtOldest: true)

    // MARK: - Variables

    /// How far one press moves the highlight.
    let step: Int
    /// Whether a quick tap, and the first highlight, is the oldest item
    /// instead of the second.
    let startsAtOldest: Bool

    /// The direction a held Shift turns this one into.
    var reversed: RecentTabSwitchDirection {
        RecentTabSwitchDirection(step: -step, startsAtOldest: !startsAtOldest)
    }

    // MARK: - Actions - Positions

    /// Where the highlight starts among `count` items: the second, or the
    /// last, and the only one when there is just one.
    func startingIndex(count: Int) -> Int {
        guard count > 1 else { return 0 }
        return startsAtOldest ? count - 1 : 1
    }

    /// The index one press from `index` among `count` items, wrapping.
    func index(from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }
}
