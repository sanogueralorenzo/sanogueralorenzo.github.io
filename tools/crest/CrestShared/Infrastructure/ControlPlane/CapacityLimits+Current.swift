import Foundation

/// The capacities the core enforces, read once. Native surfaces use them to
/// shape their UI (disable a pin action, stop offering a nested folder); the
/// core still refuses anything past them, so these are never a second
/// implementation of the rule.
extension CapacityLimits {
    // MARK: - Static Variables

    /// The packaged core's limits. The core ships inside every composition, so
    /// a refused answer is a broken build rather than a state to recover from.
    static let current: CapacityLimits = {
        do {
            return try CrestCore.answer(EnforcedLimits())
        } catch {
            preconditionFailure("The core did not report its limits: \(error)")
        }
    }()
}
