import Foundation
import Observation

@Observable
@MainActor
final class BrowserTransientActivityClock {
    private(set) var revision = 0

    @ObservationIgnored private var lastActivityAt: Date
    @ObservationIgnored private var lastPublishedActivityAt: Date
    @ObservationIgnored private let publicationInterval: TimeInterval

    init(
        now: Date = Date(),
        publicationInterval: TimeInterval = 15
    ) {
        precondition(publicationInterval >= 0)
        lastActivityAt = now
        lastPublishedActivityAt = now
        self.publicationInterval = publicationInterval
    }

    func recordActivity(
        at date: Date = Date(),
        restartsTimerImmediately: Bool = false
    ) {
        guard date >= lastActivityAt else { return }
        lastActivityAt = date
        guard
            restartsTimerImmediately
                || date.timeIntervalSince(lastPublishedActivityAt) >= publicationInterval
        else {
            return
        }
        lastPublishedActivityAt = date
        revision &+= 1
    }

    func inactivityRemaining(
        for lifetime: TimeInterval,
        at date: Date = Date()
    ) -> TimeInterval {
        max(0, lifetime - date.timeIntervalSince(lastActivityAt))
    }

    func waitUntilInactive(for lifetime: TimeInterval) async -> Bool {
        while !Task.isCancelled {
            let remaining = inactivityRemaining(for: lifetime)
            guard remaining > 0 else { return true }
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return false
            }
        }
        return false
    }
}
