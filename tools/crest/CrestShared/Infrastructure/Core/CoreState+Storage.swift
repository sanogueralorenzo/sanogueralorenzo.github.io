import Foundation

extension CoreState {
    // MARK: - Variables

    /// What the app says while the core's last save failed, until a later
    /// save succeeds.
    var storageFailureDescription: String? { storageFailure.map(Self.description(of:)) }

    // MARK: - Actions - Changes

    /// What the app says of a save the core could not finish.
    nonisolated static func description(of failure: StorageFailure) -> String {
        "The session could not be saved (\(failure))."
    }
}
