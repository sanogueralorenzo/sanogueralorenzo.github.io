import Foundation
import Observation

/// How long the welcome has waited on iCloud's check for an existing setup.
/// A few seconds in, it offers to set up without iCloud; a little later it
/// stops waiting and offers setup on its own, and the person can stop it
/// sooner by setting up without iCloud. It never cancels sync, which goes on
/// in the background: an existing setup iCloud answers with later reaches
/// this device the way it always does.
@Observable
@MainActor
final class BrowserOnboardingCloudWait {
    // MARK: - Types

    /// How far along the wait is. Each stage begins once the wait has run for
    /// `begins`.
    struct Stage: Hashable, Sendable {
        // MARK: - Static Variables

        /// The welcome waits on iCloud and offers nothing else.
        static let waiting = Stage(begins: .zero, offersSetupWithoutCloud: false, hasStopped: false)
        /// iCloud has taken a while: the welcome still waits, and offers to
        /// set up without it.
        static let offersSetupWithoutCloud = Stage(
            begins: .seconds(4), offersSetupWithoutCloud: true, hasStopped: false)
        /// The welcome no longer waits on iCloud.
        static let stopped = Stage(begins: .seconds(10), offersSetupWithoutCloud: false, hasStopped: true)
        /// Every stage, in the order they begin.
        static let all = [waiting, offersSetupWithoutCloud, stopped]

        // MARK: - Variables

        let begins: Duration
        /// Whether the welcome, still waiting, offers to set up without iCloud.
        let offersSetupWithoutCloud: Bool
        /// Whether the welcome stopped waiting on iCloud.
        let hasStopped: Bool

        // MARK: - Initializers

        /// The stage the wait reaches once it has run for `waited`.
        init(waited: Duration) {
            self = Self.all.last { $0.begins <= waited } ?? .waiting
        }

        private init(begins: Duration, offersSetupWithoutCloud: Bool, hasStopped: Bool) {
            self.begins = begins
            self.offersSetupWithoutCloud = offersSetupWithoutCloud
            self.hasStopped = hasStopped
        }
    }

    // MARK: - Variables

    private(set) var stage = Stage.waiting

    // MARK: - Actions - Waiting

    /// Moves the wait on as each stage begins, measured on `clock` from now,
    /// until it stops or the task running it ends.
    func run<WaitClock: Clock>(on clock: WaitClock = ContinuousClock()) async
    where WaitClock.Duration == Duration {
        let start = clock.now
        for next in Stage.all where next.begins > .zero {
            guard !stage.hasStopped else { return }
            do {
                try await clock.sleep(until: start.advanced(by: next.begins), tolerance: nil)
            } catch {
                return
            }
            if !stage.hasStopped { stage = Stage(waited: start.duration(to: clock.now)) }
        }
    }

    /// The person chose to set up without iCloud: the welcome stops waiting.
    func setUpWithoutCloud() {
        stage = .stopped
    }
}
