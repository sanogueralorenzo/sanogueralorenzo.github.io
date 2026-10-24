import Foundation

/// What a sidebar lift carries — a tab, a folder or a split group — and how
/// that kind of row reorders on its own. `BrowserSidebarReorderItem` hands its
/// payload over as one of these, so every rule that differs by kind lives on
/// the row it is about.
protocol BrowserSidebarDraggedItem: BrowserPlatformSidebarDraggedItem, Sendable {
    /// The row the item stands for.
    var rowID: BrowserSidebarReorderItemID { get }

    /// The window's selection the lift carries, if it carries one.
    var selection: BrowserCapturedSelection? { get }

    var spaceAssignment: BrowserSpaceRuntimeAssignment { get }

    /// The tabs and folders lifting the row alone picks.
    var rowPicks: (tabIDs: [UUID], folderIDs: [UUID]) { get }

    /// The pick that stands for the row in the window's selection.
    var firstSelectionID: BrowserSelectionItemID? { get }

    /// Whether the lift's art takes the shape of where it would land.
    var morphsIntoTarget: Bool { get }

    /// Whether a collapsed folder's header lights up the way a row does when
    /// this item would land inside it.
    var showsFolderDropHighlight: Bool { get }

    /// Whether a folder's header wears an outline around the whole row when
    /// this item would land inside it.
    var showsFolderNestOutline: Bool { get }

    /// The item lifted with the window's selection `request`.
    func selecting(_ request: BrowserCapturedSelection?) -> BrowserSidebarReorderItem

    /// The selection lifting the row alone carries, from what the core says
    /// its picks hold, `selected`, or nil when the row no longer stands for it.
    func rowSelection(from selected: SelectedTabs) -> TabSelection?

    /// Whether the row still stands in `space` where it was lifted from, in
    /// `section` and inside `parentItemID`'s row.
    @MainActor
    func stands(
        in space: SpaceModel, section: BrowserSidebarReorderSection, parentItemID: BrowserSidebarReorderItemID?
    ) -> Bool

    /// Whether `section` takes the row lifted on its own, without a selection.
    func isAcceptedAlone(by section: BrowserSidebarReorderSection) -> Bool

    /// Whether dropping the row, lifted on its own, on the open tab `tabID`
    /// may make a folder around it.
    func foldsAroundAlone(_ tabID: UUID) -> Bool

    /// Whether the row, lifted on its own, may join the cards the content area
    /// for `assignment` shows.
    func joinsCardsAlone(shownIn assignment: BrowserSpaceRuntimeAssignment) -> Bool
}
