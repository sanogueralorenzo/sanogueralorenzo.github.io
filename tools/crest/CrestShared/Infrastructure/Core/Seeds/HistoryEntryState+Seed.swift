import Foundation

extension HistoryEntryState {
    // MARK: - Initializers

    /// A visit to seed a Space's history with: `url`, visited `visitCount`
    /// times between `firstVisitedAt` and `lastVisitedAt`.
    init(
        id: UUID = UUID(), url: URL, title: String, firstVisitedAt: Date = .now, lastVisitedAt: Date = .now,
        visitCount: Int = 1
    ) {
        self.init(
            id: id, url: url.absoluteString, title: title, firstVisitedAt: firstVisitedAt,
            lastVisitedAt: lastVisitedAt, visitCount: visitCount)
    }
}
