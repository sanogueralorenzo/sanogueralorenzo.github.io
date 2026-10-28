import Foundation

/// A Space's tabs by where they sit, in the Space's order, for the views that
/// draw a Space no window shows: a preview, a draft or an import under review.
/// A window's sidebar reads its lists from `sidebar` instead.
extension SpaceModel {
    // MARK: - Variables

    var pinnedTabs: [TabStateModel] { tabs.models.filter { $0.placement == .pinned } }
    var savedTabs: [TabStateModel] { tabs.models.filter { $0.placement == .saved } }
    var currentTabs: [TabStateModel] { tabs.models.filter { !$0.placement.isDurable } }
    /// The saved tabs in no folder.
    var unfiledSavedTabs: [TabStateModel] { savedTabs.filter { $0.folderID == nil } }

    // MARK: - Actions - Reading

    /// The saved tabs in the folder `folderID`.
    func savedTabs(in folderID: UUID) -> [TabStateModel] {
        savedTabs.filter { $0.folderID == folderID }
    }
}
