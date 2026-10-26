import Foundation

enum BrowserCloudSyncActivity: Equatable, Sendable {
    case fetched(recordCount: Int)
    case uploaded(recordCount: Int)
    case accountChanged
    /// Records that arrived but could not be read, so they were left in iCloud
    /// rather than applied. `requiresAppUpdate` means a newer build wrote them.
    case skippedRecords(count: Int, requiresAppUpdate: Bool)
    /// Crest's iCloud zone stopped existing because somebody removed it.
    case cloudDataRemoved
}

/// Why the cloud transport stopped a step.
enum BrowserCloudSyncError: Error, Equatable {
    /// A change that arrived from another device could not be applied. Sync
    /// reports this instead of finishing a cycle that dropped records.
    case remoteChangeNotApplied(String)
    /// iCloud did not answer whether an account is signed in before the
    /// check's deadline.
    case accountCheckUnanswered
}

enum BrowserCloudSyncStatus: Equatable, Sendable {
    case stopped
    case syncing
    case idle
    case pausedForAccountConfirmation
    case failed(String)
}
