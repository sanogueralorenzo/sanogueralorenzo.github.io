import Foundation

extension Sequence<DownloadState> {
    // MARK: - Variables

    /// The progress a downloads badge shows: the newest live download's, or
    /// nil when none is live.
    var notificationProgress: Double? {
        filter { $0.phase.isLive }
            .max { $0.createdAt < $1.createdAt }
            .map(\.progress)
    }
}
