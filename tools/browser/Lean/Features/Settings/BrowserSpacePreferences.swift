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

struct BrowserSpacePreferences: Codable, Equatable {
    var blocksContent = true
    var historyRetention = BrowserDataRetention.forever
    var archiveRetention = BrowserDataRetention.forever
    var downloadRetention = BrowserDataRetention.forever
}

extension BrowserStore {
    func spacePreferences(_ id: UUID) -> BrowserSpacePreferences {
        session.spaces.first { $0.id == id }?.browsingPreferences
            ?? BrowserSpacePreferences(blocksContent: preferences.blocksContent)
    }

    func updateSpacePreferences(_ id: UUID, _ update: (inout BrowserSpacePreferences) -> Void) {
        guard let index = session.spaces.firstIndex(where: { $0.id == id }) else { return }
        let previous = spacePreferences(id)
        var value = previous
        update(&value)
        session.spaces[index].browsingPreferences = value
        if previous.blocksContent != value.blocksContent {
            for page in pages.values where page.spaceID == id {
                page.applyContentBlocking()
                Task {
                    await page.waitForContentBlocking()
                    page.webView.reload()
                }
            }
        }
        owner.sweepExpiredRecords(force: true)
        changed()
    }

    func setDefaultPageZoom(_ zoom: Double) {
        guard zoom.isFinite, (0.25...5).contains(zoom) else { return }
        let previous = preferences.defaultPageZoom ?? 1
        for s in session.spaces.indices {
            for t in session.spaces[s].tabs.indices {
                let id = session.spaces[s].tabs[t].id
                let current = pages[id].map { Double($0.webView.pageZoom) } ?? session.spaces[s].tabs[t].zoom
                if abs(current - previous) < 0.0001 {
                    session.spaces[s].tabs[t].zoom = zoom
                    pages[id]?.webView.pageZoom = zoom
                }
            }
        }
        updatePreferences { $0.defaultPageZoom = zoom }
    }
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
