import Foundation
import Observation

/// The launch gate setup holds shut until it finishes.
///
/// The core decides whether setup holds this launch's windows back: on a
/// device that has not completed setup, which it keeps in its device store
/// having adopted what an installed release kept, or in a launch that forces
/// setup, as a review or test launch does, until setup finishes in this run.
@Observable
@MainActor
final class BrowserOnboardingProgressStore {
    // MARK: - Variables

    @ObservationIgnored let core: CrestCore
    /// The launch the gate answers for, as the core reads it.
    @ObservationIgnored private let environment: LaunchEnvironment
    /// Whether this launch forces setup whatever the device completed.
    let forcesSetup: Bool
    /// How many times setup finished in this run, so a view that asked
    /// whether the gate holds asks again.
    private var finishes = 0

    /// Whether the device has completed setup, as far as this launch asks.
    var hasCompletedSetup: Bool {
        !forcesSetup && core.state.setupCompleted == true
    }

    /// Whether setup holds this launch's windows back, as the core answers.
    var isLaunchGateActive: Bool {
        // The answer follows what these say; reading them asks again when they change.
        _ = finishes
        let completed = core.state.setupCompleted == true
        guard let gate = try? core.query(LaunchSetup(environment: environment)) else { return !completed }
        return gate.setup != nil
    }

    var shouldPresentWelcome: Bool { isLaunchGateActive }

    // MARK: - Initializers

    /// A gate over `core`, which has adopted whether the device completed
    /// setup, for a launch in `environment`. `forcesSetup` says the launch
    /// forces setup on this platform.
    init(core: CrestCore, environment: LaunchEnvironment, forcesSetup: Bool = false) {
        self.core = core
        self.environment = environment
        self.forcesSetup = forcesSetup
    }

    // MARK: - Actions - Finishing

    /// Setup finished in this run: the core opens the gate.
    func setupFinished() {
        finishes += 1
    }
}
