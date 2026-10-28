import Foundation

extension FolderState.Seed {
    // MARK: - Initializers

    /// A folder to seed a Space with, among the saved tabs unless placed
    /// elsewhere, at the top level unless `parentID` names its parent, and
    /// open.
    init(
        id: UUID = UUID(),
        title: String,
        location: TabPlacement = .saved,
        color: BrandColor? = nil,
        parentID: UUID? = nil,
        isCollapsed: Bool = false,
        collapseModifiedAt: Date? = nil,
        orderAnchorTabID: UUID? = nil,
        source: LiveFolderSource? = nil,
        liveOptions: GitHubLiveFolderOptions? = nil
    ) {
        self.init(
            id: id, location: location, title: title, color: color, parentID: parentID,
            isCollapsed: isCollapsed, collapseModifiedAt: collapseModifiedAt, orderAnchorTabID: orderAnchorTabID,
            source: source, liveOptions: liveOptions)
    }
}
