import Foundation

/// Does what a download row asks, the way one shell does it: one method per
/// step a `BrowserUtilityDownloadAction` takes. Each is called only once the
/// shell has confirmed the row's Space still owns `item`.
@MainActor
protocol BrowserDownloadActionPerformer {
    func openDownload(_ item: DownloadState, in destination: BrowserUtilityDownloadDestination)
    func retryDownload(_ item: DownloadState, matching assignment: BrowserSpaceRuntimeAssignment)
    func pauseDownload(_ item: DownloadState)
    func resumeDownload(_ item: DownloadState)
    func cancelDownload(_ item: DownloadState)
    func clearDownload(_ item: DownloadState)
}
