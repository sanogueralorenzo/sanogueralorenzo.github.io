import SwiftUI

struct MobileDownloadsView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MobileDownloadsContent(
            space: space,
            downloads: downloads,
            actions: actions,
            dismiss: dismiss.callAsFunction
        )
    }

    private var downloads: [DownloadState] {
        guard let space else { return [] }
        return pages.downloadCenter.items(for: space.profileID)
    }

    private var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            downloadDestinations: [.share, .files],
            performDownloadAction: performDownloadAction
        )
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching rowAssignment: BrowserSpaceRuntimeAssignment
    ) {
        guard rowAssignment == assignment,
            let item = downloadItem(for: action)
        else { return }
        action.perform(on: self, for: item, matching: assignment)
    }

    private func downloadItem(
        for action: BrowserUtilityDownloadAction
    ) -> DownloadState? {
        action.downloadItem(
            matching: assignment, in: browser, accessController: spaceAccess,
            itemsForProfile: pages.downloadCenter.items(for:))
    }

    private var space: SpaceModel? {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
    }
}

// MARK: - Actions - Downloads

extension MobileDownloadsView: BrowserDownloadActionPerformer {
    func openDownload(_ item: DownloadState, in destination: BrowserUtilityDownloadDestination) {
        if let export = MobileBrowserFileExportDestination.exporting(destination) {
            pages.exportDownload(item.id, to: export)
        }
    }

    func retryDownload(_ item: DownloadState, matching assignment: BrowserSpaceRuntimeAssignment) {
        pages.downloadCenter.retryAutomaticDownload(item.id, matching: assignment) { expectedAssignment in
            browser.unlockedSpace(matching: expectedAssignment, accessController: spaceAccess) != nil
        }
    }

    func pauseDownload(_ item: DownloadState) {
        pages.downloadCenter.pause(item.id)
    }

    func resumeDownload(_ item: DownloadState) {
        pages.downloadCenter.resume(item.id)
    }

    func cancelDownload(_ item: DownloadState) {
        pages.cancelDownload(item.id)
    }

    func clearDownload(_ item: DownloadState) {
        pages.clearDownload(item.id)
    }
}
