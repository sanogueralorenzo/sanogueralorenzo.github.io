import Foundation

extension BrowserUtilityDownloadAction {
    // MARK: - Actions - Access

    /// The download the action names, among `itemsForProfile`'s for the Space
    /// at `assignment`, or nil unless `browser` shows that Space selected and
    /// unlocked and the download belongs to its profile.
    @MainActor
    func downloadItem(
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController,
        itemsForProfile: (UUID) -> [DownloadState]
    ) -> DownloadState? {
        guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: accessController)
        else { return nil }
        return itemsForProfile(space.profileID).first {
            $0.id == itemID && $0.profileID == assignment.profileID
        }
    }
}
