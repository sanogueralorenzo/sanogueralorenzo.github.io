import Foundation

extension BrowserSplitGroupDragItem: BrowserSidebarDraggedItem {
    // MARK: - Variables

    var rowID: BrowserSidebarReorderItemID { .splitGroup(groupID) }

    /// Lifting a split's row alone picks every member of the split.
    var rowPicks: (tabIDs: [UUID], folderIDs: [UUID]) { (memberTabIDs, []) }

    /// The first member of the split stands for the row.
    var firstSelectionID: BrowserSelectionItemID? { memberTabIDs.first.map(BrowserSelectionItemID.tab) }

    /// A split keeps its own art.
    var morphsIntoTarget: Bool { false }

    var showsFolderDropHighlight: Bool { false }

    /// A split group can never appear here: it moves as one block and refuses
    /// folder zones outright.
    var showsFolderNestOutline: Bool { false }

    // MARK: - Actions - Lifting

    func selecting(_ request: BrowserCapturedSelection?) -> BrowserSidebarReorderItem {
        var item = self
        item.selection = request
        return .splitGroup(item)
    }

    /// A split row lifts the run it stood for; one the Space no longer holds
    /// as that split plans nothing.
    func rowSelection(from selected: SelectedTabs) -> TabSelection? {
        guard selected.members.map(\.id) == memberTabIDs,
            selected.members.allSatisfy({ $0.splitGroupID == groupID })
        else { return nil }
        return selected.selection
    }

    /// A split still stands while it holds the members it stood for.
    @MainActor
    func stands(
        in space: SpaceModel, section: BrowserSidebarReorderSection, parentItemID: BrowserSidebarReorderItemID?
    ) -> Bool {
        let members = space.splitMembers(of: groupID)
        guard let first = members.first, members.map(\.id) == memberTabIDs else { return false }
        return section == .tabs(placement: first.placement, folderID: first.folderID)
    }

    // MARK: - Actions - Targets

    /// A split group is a run of tabs and reorders among tabs, but pinned tabs
    /// cannot be members, so the pinned grid refuses it the same way it
    /// refuses a folder.
    func isAcceptedAlone(by section: BrowserSidebarReorderSection) -> Bool {
        guard case .tabs(let placement, _) = section else { return false }
        return placement.holdsSplits
    }

    func foldsAroundAlone(_ tabID: UUID) -> Bool {
        !memberTabIDs.contains(tabID)
    }

    /// A split joins the cards on show as one block. Splits never span
    /// Spaces, so a lift from elsewhere is refused here rather than relocated
    /// first.
    func joinsCardsAlone(shownIn assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        spaceAssignment == assignment
    }
}
