import Foundation

extension BrowserTabDragItem: BrowserSidebarDraggedItem {
    // MARK: - Variables

    var rowID: BrowserSidebarReorderItemID { .tab(tabID) }

    /// Lifting a tab's row alone picks the tab.
    var rowPicks: (tabIDs: [UUID], folderIDs: [UUID]) { ([tabID], []) }

    var firstSelectionID: BrowserSelectionItemID? { .tab(tabID) }

    /// A tab morphs between its row, the pinned tile and the page card.
    var morphsIntoTarget: Bool { true }

    /// A tab filed into a folder becomes one of the folder's rows, so a row's
    /// own selection treatment is the honest preview of what release does.
    var showsFolderDropHighlight: Bool { true }

    var showsFolderNestOutline: Bool { false }

    // MARK: - Actions - Lifting

    func selecting(_ request: BrowserCapturedSelection?) -> BrowserSidebarReorderItem {
        var item = self
        item.selection = request
        return .tab(item)
    }

    func rowSelection(from selected: SelectedTabs) -> TabSelection? {
        selected.selection
    }

    @MainActor
    func stands(
        in space: SpaceModel, section: BrowserSidebarReorderSection, parentItemID: BrowserSidebarReorderItemID?
    ) -> Bool {
        guard let tab = space.tabs.model(tabID),
            space.shownSplit(containing: tab.id).map(BrowserSidebarReorderItemID.splitGroup) == parentItemID
        else { return false }
        return section == .tabs(placement: tab.placement, folderID: tab.folderID)
    }

    // MARK: - Actions - Targets

    /// A tab reorders only among tabs.
    func isAcceptedAlone(by section: BrowserSidebarReorderSection) -> Bool {
        if case .tabs = section { return true }
        return false
    }

    func foldsAroundAlone(_ tabID: UUID) -> Bool {
        self.tabID != tabID
    }

    /// Only a tab of the same Space becomes a card.
    func joinsCardsAlone(shownIn assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        spaceAssignment == assignment
    }
}
