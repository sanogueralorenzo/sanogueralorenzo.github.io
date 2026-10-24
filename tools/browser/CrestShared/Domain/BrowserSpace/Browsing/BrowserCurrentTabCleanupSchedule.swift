import Foundation

/// Cadence for re-applying each Space's tab cleanup and stored-data retention
/// policies while a scene is active.
///
/// Cleanup used to run only while a store was being built, so a session that
/// stayed open for days never archived anything. The policies are hour-granular,
/// so a low-frequency sweep keeps up with them, and pinning the cadence here
/// keeps it testable instead of buried in a scene.
enum BrowserCurrentTabCleanupSchedule {
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
