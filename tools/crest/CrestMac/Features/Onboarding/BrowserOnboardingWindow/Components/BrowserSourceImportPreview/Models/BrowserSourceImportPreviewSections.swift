import Foundation

/// The reviewed Space's tabs by the placement each comes in with.
@MainActor
struct BrowserSourceImportPreviewSections {
    let pinnedTabs: [TabStateModel]
    let savedTabs: [TabStateModel]
    let currentTabs: [TabStateModel]
    let savedTabsByFolderID: [UUID: [TabStateModel]]
    let unfiledSavedTabs: [TabStateModel]

    init(review: BrowserImportSpaceReview) {
        var pinnedTabs: [TabStateModel] = []
        var savedTabs: [TabStateModel] = []
        var currentTabs: [TabStateModel] = []
        var savedTabsByFolderID: [UUID: [TabStateModel]] = [:]
        var unfiledSavedTabs: [TabStateModel] = []

        for tab in review.sourceSpace.tabs.models {
            let placement = review.placement(for: tab)
            if !placement.isDurable {
                currentTabs.append(tab)
            } else if !placement.holdsFolders {
                pinnedTabs.append(tab)
            } else {
                savedTabs.append(tab)
                if let folderID = tab.folderID {
                    savedTabsByFolderID[folderID, default: []].append(tab)
                } else {
                    unfiledSavedTabs.append(tab)
                }
            }
        }

        self.pinnedTabs = pinnedTabs
        self.savedTabs = savedTabs
        self.currentTabs = currentTabs
        self.savedTabsByFolderID = savedTabsByFolderID
        self.unfiledSavedTabs = unfiledSavedTabs
    }
}
