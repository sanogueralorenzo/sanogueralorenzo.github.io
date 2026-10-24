import Foundation

extension LaunchDecision {
    // MARK: - Static Variables

    /// What a launch does when the core cannot answer: stay out of the
    /// installed profile and forget everything, and open the documented
    /// default destination.
    static let unavailable = LaunchDecision(
        requiresIsolation: true, usesEphemeralProfileStorage: true, presentsInstalledApplicationUI: false,
        startup: .showStartPage)
}
