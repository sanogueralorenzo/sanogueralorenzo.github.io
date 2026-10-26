import Foundation

extension BrowserFolderDragItem: BrowserSidebarDraggedItem {
    // MARK: - Variables

    var rowID: BrowserSidebarReorderItemID { .folder(folderID) }

    /// Lifting a folder's row alone picks the folder with all it holds.
    var rowPicks: (tabIDs: [UUID], folderIDs: [UUID]) { ([], [folderID]) }

    var firstSelectionID: BrowserSelectionItemID? { .folder(folderID) }

    /// A folder keeps its own art.
    var morphsIntoTarget: Bool { false }

    var showsFolderDropHighlight: Bool { false }

    /// A folder filed inside another changes the structure rather than the
    /// contents, and an outline says "inside this one" where a row highlight
    /// would only say "one of these".
    var showsFolderNestOutline: Bool { true }

    // MARK: - Actions - Lifting

    func selecting(_ request: BrowserCapturedSelection?) -> BrowserSidebarReorderItem {
        var item = self
        item.selection = request
        return .folder(item)
    }

    /// A folder lifted with the tabs it held then drops only while it holds
    /// them still; the core refuses a selection whose tabs changed.
    func rowSelection(from selected: SelectedTabs) -> TabSelection? {
        guard let snapshot = memberTabIDs else { return selected.selection }
        return TabSelection(
            tabIDs: selected.selection.tabIDs, folderIDs: selected.selection.folderIDs, memberTabIDs: snapshot)
    }

    @MainActor
    func stands(
        in space: SpaceModel, section: BrowserSidebarReorderSection, parentItemID: BrowserSidebarReorderItemID?
    ) -> Bool {
        space.folders.model(folderID)?.reorderSection == section
    }

    // MARK: - Actions - Targets

    /// A folder reorders only among folders, so a folder dragged over the
    /// pinned grid resolves to no target rather than a nonsensical one.
    func isAcceptedAlone(by section: BrowserSidebarReorderSection) -> Bool {
        guard case .tabs(let placement, _) = section else { return true }
        return placement.holdsFolders
    }

    func foldsAroundAlone(_ tabID: UUID) -> Bool {
        false
    }

    /// A folder has no page to show.
    func joinsCardsAlone(shownIn assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        false
    }
}
