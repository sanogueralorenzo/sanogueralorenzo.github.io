import Foundation

/// A download leaving the place it started, shown as it flies to its list.
struct BrowserDownloadFeedbackEvent: Identifiable, Equatable, @unchecked Sendable {
    // MARK: - Static Variables

    /// How many departures show at once; an older one gives way to a newer.
    static let maximumVisible = 3
    /// How long one departure stays on screen.
    static let lifetime: Duration = .milliseconds(1_400)

    // MARK: - Variables

    let id: UUID
    let profileID: UUID
    let spaceID: UUID
    let filename: String
    let source: BrowserDownloadFeedbackSource

    // MARK: - Actions - Showing

    /// The events on screen once this one joins `events`, keeping only the newest.
    func appended(to events: [BrowserDownloadFeedbackEvent]) -> [BrowserDownloadFeedbackEvent] {
        Array((events + [self]).suffix(Self.maximumVisible))
    }
}
