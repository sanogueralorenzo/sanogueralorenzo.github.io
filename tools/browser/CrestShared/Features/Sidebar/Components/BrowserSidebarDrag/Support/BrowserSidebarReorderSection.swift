import Foundation

/// An ordered run of sidebar rows that a lifted item can be inserted into.
///
/// Folders and tabs are separate sections even where they render in the same
/// visual column, because a folder reorders among its siblings while a tab
/// reorders among the tabs of a placement.
enum BrowserSidebarReorderSection: Hashable, Sendable {
    case tabs(placement: TabPlacement, folderID: UUID?)
    case folders(parentID: UUID?)

    // MARK: - Variables

    /// How deeply this run is nested inside the sidebar's own runs.
    ///
    /// A folder's rows are a run inside the run of the placement that holds the
    /// folder, and the two can measure the very same rectangle: a saved list
    /// whose only content is one folder group *is* that folder group, because a
    /// `VStack` around a single child takes the child's frame. Nesting is
    /// structural rather than a matter of pixels, so it is what decides which of
    /// two overlapping runs owns a pointer.
    var nestingDepth: Int {
        switch self {
        case .tabs(_, let folderID): folderID == nil ? 0 : 1
        case .folders(let parentID): parentID == nil ? 0 : 1
        }
    }

    /// A section of tabs that lays out as a grid orders on both axes.
    var usesGridOrdering: Bool {
        switch self {
        case .tabs(let placement, _): placement.isGrid
        case .folders: false
        }
    }

    /// Grids insert between columns, so their drop indicator is vertical.
    var flowsHorizontally: Bool {
        usesGridOrdering
    }

    /// The folder whose inside this run is, or nil for a run at the top level.
    var parentFolderID: UUID? {
        switch self {
        case .tabs(_, let folderID): folderID
        case .folders(let parentID): parentID
        }
    }

    /// The shape a lifted tab takes resting in this run: a pinned tile in the
    /// grid, a row in a list, or none for a run of folders.
    var restingPreviewShape: BrowserTabDragPreviewShape? {
        guard case .tabs(let placement, _) = self else { return nil }
        return .resting(for: placement)
    }

    // MARK: - Actions - Targets

    /// The list among the core's drop `targets` this run inserts into: the
    /// placement and folder of a run of tabs, or the inside of a run of
    /// folders' parent, which at the top level is the saved list.
    func list(in targets: DropTargetList) -> ListDropTarget? {
        switch self {
        case .tabs(let placement, let folderID):
            targets.lists.first { $0.section == placement && $0.folderID == folderID }
        case .folders(let parentID):
            targets.lists.first { $0.folderID == parentID && (parentID != nil || $0.section == .saved) }
        }
    }

    /// The list of `space`'s sidebar this run is: the placement and folder of
    /// a run of tabs, or the inside of a run of folders' parent, in that
    /// folder's placement, which at the top level is the saved list.
    @MainActor
    func list(in space: SpaceModel) -> (placement: TabPlacement, folderID: UUID?) {
        switch self {
        case .tabs(let placement, let folderID):
            (placement, folderID)
        case .folders(let parentID):
            (parentID.flatMap { space.folders.model($0)?.location } ?? .saved, parentID)
        }
    }

    // MARK: - Actions - Rows

    /// Rows belonging to this section, in their current visual order.
    func rows(from rows: [BrowserSidebarReorderRow]) -> [BrowserSidebarReorderRow] {
        rows.filter { $0.section == self }.sorted { $0.precedes($1) }
    }
}
