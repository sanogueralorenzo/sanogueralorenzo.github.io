import Foundation

extension SessionState.Seed {
    // MARK: - Variables

    /// The session a first launch starts with when nothing is carried to it,
    /// as the core describes it, for a launch without a file to open. Each
    /// read has identities of its own.
    static var firstInstall: SessionState.Seed {
        do {
            return try CrestCore.answer(FirstInstallSession()).seed
        } catch {
            preconditionFailure("The core must describe the session a first launch starts with: \(error)")
        }
    }
}
