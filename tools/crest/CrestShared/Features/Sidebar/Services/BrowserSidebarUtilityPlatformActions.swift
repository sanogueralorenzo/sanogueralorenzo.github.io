import Foundation

@MainActor
struct BrowserSidebarUtilityPlatformActions {
    /// Where a finished download can be sent, in the order the surface offers
    /// them. Plain data: the shells differ on the list, not on how it is read.
    let downloadDestinations: [BrowserUtilityDownloadDestination]

    /// Opens a history entry in whatever "somewhere new" means for this shell.
    let openHistoryEntry: (URL, BrowserSpaceRuntimeAssignment) -> Void

    /// Brings a tab the coordinator just pulled out of the archive on screen.
    let selectRestoredTab: (UUID) -> Void

    /// Hands a finished download to the destination the reader picked. Each
    /// shell checks that the file is really there in its own way.
    let openFinishedDownload: (DownloadState, BrowserUtilityDownloadDestination) -> Void

    /// Stops a download that is still running.
    let cancelDownload: (UUID) -> Void

    /// Drops a download from the list without touching the file on disk.
    let clearDownload: (UUID) -> Void
}
