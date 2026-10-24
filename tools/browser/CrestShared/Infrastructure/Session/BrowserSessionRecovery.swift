import Foundation

/// A launch that could not open the core's session file, and what the recovery
/// screen may offer for it.
struct BrowserSessionStartupFailure: Error {
    /// The directory the core keeps its session in, when the launch got as far
    /// as naming one.
    let storageDirectory: URL?
    let underlying: Error

    /// The file was written by a newer release, which a restore must not undo.
    var requiresNewerApp: Bool {
        if case .storageFromNewerApp = underlying as? Rejection { return true }
        return false
    }

    var checkpointDate: Date? {
        guard !requiresNewerApp, let storageDirectory else { return nil }
        return try? BrowserSessionRecovery.checkpointURL(in: storageDirectory)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Puts the recovery checkpoint in place of the session file. The core
    /// keeps the failed file and its sidecars beside it, and throws the
    /// rejection naming why it could not.
    func restore() throws {
        guard !requiresNewerApp, let storageDirectory else { throw BrowserSessionRecovery.RecoveryError.unavailable }
        try CrestCore.restoreRecoveryCheckpoint(
            configuration: AppConfiguration(storageDirectory: storageDirectory.path))
    }
}

/// What the recovery screen reads beside the core's session file. The core
/// writes the file, its recovery checkpoint and the cloud-recovery marker, and
/// consumes that marker itself when the cloud transport's state starts over;
/// this side only reports the checkpoint's age.
enum BrowserSessionRecovery {
    enum RecoveryError: Error {
        /// Nothing may be restored over this file.
        case unavailable
    }

    private static let checkpointName = "session.recovery.sqlite"

    static func checkpointURL(in directory: URL) -> URL { directory.appendingPathComponent(checkpointName) }
}
