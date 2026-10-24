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
        symbol: String? = nil,
        color: BrandColor? = nil,
        parentID: UUID? = nil,
        isCollapsed: Bool = false,
        collapseModifiedAt: Date? = nil,
        orderAnchorTabID: UUID? = nil
    ) {
        self.init(
            id: id, location: location, title: title, symbol: symbol, color: color, parentID: parentID,
            isCollapsed: isCollapsed, collapseModifiedAt: collapseModifiedAt, orderAnchorTabID: orderAnchorTabID)
    }
}
