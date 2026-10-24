import Foundation

/// The archive, history, and downloads actions the sidebar's utility surfaces
/// perform, behind the one access guard they all share.
///
/// Every action re-reads the session at call time and refuses unless the Space
/// the caller named is still the selected, unlocked one it owns — the surfaces
/// hand out captured closures, and a Space can be reselected, relocked, deleted,
/// or have its profile replaced between the capture and the tap. Only the last
/// step of each action differs between the shells; that step comes from
/// `BrowserSidebarUtilityPlatformActions`.
@MainActor
struct BrowserSidebarUtilityCoordinator {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceAccess: BrowserSpaceAccessController
    let platformActions: BrowserSidebarUtilityPlatformActions

    var selectedDownloads: [DownloadState] {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return [] }
        return downloadCenter.items(for: space.profileID)
    }

    var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            restoreArchivedTab: restoreArchivedTab,
            openHistoryEntry: openHistoryEntry,
            downloadDestinations: platformActions.downloadDestinations,
            performDownloadAction: performDownloadAction
        )
    }

    func acknowledgeDownloads(ifPresented surface: BrowserUtilitySurface?) {
        guard surface == .downloads, let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return }
        downloadCenter.acknowledgeItems(for: space.profileID)
    }

    private func restoreArchivedTab(
        _ tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            browser.restoreArchivedTab(tabID, matching: assignment)
        else { return }
        platformActions.selectRestoredTab(tabID)
    }

    private func openHistoryEntry(
        _ entry: HistoryEntryState,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            let url = URL(string: entry.url)
        else { return }
        platformActions.openHistoryEntry(url, assignment)
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard let item = downloadItem(for: action, matching: assignment) else {
            return
        }
        action.perform(on: self, for: item, matching: assignment)
    }

    private func downloadItem(
        for action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> DownloadState? {
        action.downloadItem(
            matching: assignment, in: browser, accessController: spaceAccess,
            itemsForProfile: downloadCenter.items(for:))
    }
}

// MARK: - Actions - Downloads

extension BrowserSidebarUtilityCoordinator: BrowserDownloadActionPerformer {
    func openDownload(_ item: DownloadState, in destination: BrowserUtilityDownloadDestination) {
        platformActions.openFinishedDownload(item, destination)
    }

    func retryDownload(_ item: DownloadState, matching assignment: BrowserSpaceRuntimeAssignment) {
        downloadCenter.retryAutomaticDownload(item.id, matching: assignment) { expectedAssignment in
            browser.unlockedSpace(matching: expectedAssignment, accessController: spaceAccess) != nil
        }
    }

    func pauseDownload(_ item: DownloadState) {
        downloadCenter.pause(item.id)
    }

    func resumeDownload(_ item: DownloadState) {
        downloadCenter.resume(item.id)
    }

    func cancelDownload(_ item: DownloadState) {
        platformActions.cancelDownload(item.id)
    }

    func clearDownload(_ item: DownloadState) {
        platformActions.clearDownload(item.id)
    }
}
