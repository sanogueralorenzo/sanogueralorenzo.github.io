import Foundation

/// Cadence for expiring stored history, archive, and download records.
enum BrowserDataRetentionSchedule {
    /// How long an active scene waits between sweeps.
    static let sweepInterval: TimeInterval = 15 * 60

    /// Shortest gap between two sweeps of the download ledger. Several windows
    /// becoming active at once, or an activation landing on top of a periodic
    /// tick, collapse into a single pass instead of racing each other. The
    /// core spaces the session's own sweeps the same way.
    static let minimumSweepSpacing: TimeInterval = 60

    static func allowsSweep(lastSweptAt: Date?, now: Date) -> Bool {
        guard let lastSweptAt else { return true }
        let elapsed = now.timeIntervalSince(lastSweptAt)
        // A backwards clock adjustment must not wedge the sweep shut.
        guard elapsed >= 0 else { return true }
        return elapsed >= minimumSweepSpacing
    }
}
