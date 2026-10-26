import Foundation

struct BrowserCollapsedFolderTabVisibilityState: Equatable {
    private(set) var keptTabID: UUID?

    mutating func expansionDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        folderTabIDs: [UUID]
    ) {
        guard !isExpanded else {
            keptTabID = nil
            return
        }
        keptTabID = selectedTabID.flatMap { selectedTabID in
            folderTabIDs.contains(selectedTabID) ? selectedTabID : nil
        }
    }

    mutating func selectionDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        folderTabIDs: [UUID]
    ) {
        guard !isExpanded,
            let selectedTabID,
            folderTabIDs.contains(selectedTabID)
        else { return }
        keptTabID = selectedTabID
    }

    mutating func residencyDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        residentFolderTabIDs: [UUID]
    ) {
        if let keptTabID,
            !residentFolderTabIDs.contains(keptTabID)
        {
            self.keptTabID = nil
        }
        guard !isExpanded,
            let selectedTabID,
            residentFolderTabIDs.contains(selectedTabID)
        else { return }
        keptTabID = selectedTabID
    }

    mutating func tabDidUnload(_ tabID: UUID) {
        guard keptTabID == tabID else { return }
        keptTabID = nil
    }
}
