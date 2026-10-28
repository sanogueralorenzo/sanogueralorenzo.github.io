import Foundation

extension BrowserUtilityDownloadAction {
    // MARK: - Actions - Access

    @MainActor
    func downloadItem(
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        itemsForProfile: (UUID) -> [DownloadState]
    ) -> DownloadState? {
        guard let space = browser.selectedAvailableSpace(matching: assignment)
        else { return nil }
        return itemsForProfile(space.profileID).first {
            $0.id == itemID && $0.profileID == assignment.profileID
        }
    }
}
