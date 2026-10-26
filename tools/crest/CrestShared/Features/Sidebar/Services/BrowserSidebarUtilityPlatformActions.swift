import Foundation

/// The handful of places the two shells answer a utility action differently.
///
/// The guards, the retry flow, and the acknowledge and items plumbing are the
/// same on both sides and stay in `BrowserSidebarUtilityCoordinator`. What
/// differs is only where a page ends up: the windowed shell opens a tab in
/// place and hands finished files to Finder, while the compact shell routes a
/// URL through its navigation and hands files to the share sheet. Those arrive
/// here as closures rather than behind a protocol — there is no third shell to
/// swap in, only two bindings each platform makes in its own extension.
///
/// Every closure is called only after the coordinator has confirmed the caller
/// still owns the selected, unlocked Space, so none of them re-checks access.
/// None carries an isolation annotation, exactly like the
/// `BrowserUtilityListActions` they feed: the compact shell binds navigation
/// closures its sidebar View is holding, and those are plain function values.
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
