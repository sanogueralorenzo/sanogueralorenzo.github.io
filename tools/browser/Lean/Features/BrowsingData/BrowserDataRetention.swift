import Foundation

enum BrowserDataRetention: Int, Codable, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case year = 365
    case forever = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "30 Days"
        case .threeMonths: "90 Days"
        case .year: "1 Year"
        case .forever: "Forever"
        }
    }
    func cutoff(at now: Date) -> Date? { self == .forever ? nil : now.addingTimeInterval(-Double(rawValue) * 86400) }
}

extension BrowserSessionOwner {
    func sweepExpiredRecords(now: Date = Date(), force: Bool = false) {
        guard force || now.timeIntervalSince(lastRetentionSweep) >= 60 else { return }
        lastRetentionSweep = now
        let oldCount = session.history.count + session.archive.count + session.downloads.count
        for space in session.spaces {
            guard let preferences = space.browsingPreferences else { continue }
            if let cutoff = preferences.historyRetention.cutoff(at: now) {
                session.history.removeAll { $0.spaceID == space.id && $0.date < cutoff }
            }
            if let cutoff = preferences.archiveRetention.cutoff(at: now) {
                session.archive.removeAll { $0.spaceID == space.id && $0.date < cutoff }
            }
            if let cutoff = preferences.downloadRetention.cutoff(at: now) {
                session.downloads.removeAll {
                    $0.spaceID == space.id && $0.date < cutoff && ![.running, .paused, .choosing].contains($0.status)
                }
            }
        }
        if session.history.count + session.archive.count + session.downloads.count != oldCount { changed() }
    }
}
