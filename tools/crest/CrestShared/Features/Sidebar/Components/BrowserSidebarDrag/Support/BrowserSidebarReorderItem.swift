import Foundation

/// Something the sidebar can reorder in place. Tabs, folders, and split groups
/// share the same lift, displacement, and drop-indicator machinery; only the
/// committed move differs.
enum BrowserSidebarReorderItem: Equatable, Sendable {
    case tab(BrowserTabDragItem)
    case folder(BrowserFolderDragItem)
    /// The group header moves all members together.
    case splitGroup(BrowserSplitGroupDragItem)

    // MARK: - Variables

    /// The item's payload, which carries every rule that differs by kind.
    var dragged: any BrowserSidebarDraggedItem {
        switch self {
        case .tab(let item): item
        case .folder(let item): item
        case .splitGroup(let item): item
        }
    }

    var id: BrowserSidebarReorderItemID { dragged.rowID }

    var selection: BrowserCapturedSelection? { dragged.selection }

    var selectionRowIDs: Set<BrowserSidebarReorderItemID> {
        guard let selection else { return [id] }
        let members = Dictionary(uniqueKeysWithValues: selection.members.map { ($0.id, $0) })
        return Set(
            selection.rootItems.map {
                switch $0 {
                case .folder(let id): return .folder(id)
                case .tab(let id):
                    if let member = members[id], let group = member.splitGroupID, member.placement.holdsSplits {
                        return .splitGroup(group)
                    }
                    return .tab(id)
                }
            })
    }

    var selectionHiddenRowIDs: Set<BrowserSidebarReorderItemID> {
        guard let selection else { return [id] }
        return selectionRowIDs.union(selection.folderIDs.map(Self.folderRowID))
            .union(
                selection.members.map { member in
                    member.splitGroupID.map(BrowserSidebarReorderItemID.splitGroup) ?? .tab(member.id)
                })
    }

    private static func folderRowID(_ id: UUID) -> BrowserSidebarReorderItemID { .folder(id) }

    var spaceAssignment: BrowserSpaceRuntimeAssignment { dragged.spaceAssignment }

    /// The tabs and folders lifting the row alone picks: a tab, every member
    /// of a split, or a folder with all it holds.
    var rowPicks: (tabIDs: [UUID], folderIDs: [UUID]) { dragged.rowPicks }

    /// The pick that stands for the row in the window's selection: the tab,
    /// the first member of a split, or the folder.
    var firstSelectionID: BrowserSelectionItemID? { dragged.firstSelectionID }

    /// Whether the lift's art takes the shape of where it would land. A tab
    /// morphs between its row, the pinned tile and the page card; a folder or
    /// a split keeps its own art.
    var morphsIntoTarget: Bool { dragged.morphsIntoTarget }

    /// Whether a collapsed folder's header lights up the way a row does when
    /// this lift would land inside it.
    var showsFolderDropHighlight: Bool { dragged.showsFolderDropHighlight }

    /// Whether a folder's header wears an outline around the whole row when
    /// this lift would land inside it.
    var showsFolderNestOutline: Bool { dragged.showsFolderNestOutline }

    // MARK: - Actions - Lifting

    /// The item lifted with the window's selection `request`.
    func selecting(_ request: BrowserCapturedSelection?) -> Self {
        dragged.selecting(request)
    }

    /// The selection lifting the row alone carries, from what the core says
    /// its picks hold, `selected`, or nil when the row no longer stands for
    /// it. A split row lifts the run it stood for; one the Space no longer
    /// holds as that split plans nothing. A folder lifted with the tabs it
    /// held then drops only while it holds them still; the core refuses a
    /// selection whose tabs changed.
    func rowSelection(from selected: SelectedTabs) -> TabSelection? {
        dragged.rowSelection(from: selected)
    }

    /// Whether the row still stands in `space` where it was lifted from, in
    /// `section` and inside `parentItemID`'s row: the Space still lists it
    /// there, and a split still holds the members it stood for.
    @MainActor
    func stands(
        in space: SpaceModel, section: BrowserSidebarReorderSection, parentItemID: BrowserSidebarReorderItemID?
    ) -> Bool {
        dragged.stands(in: space, section: section, parentItemID: parentItemID)
    }

    // MARK: - Actions - Targets

    /// Whether a section will take this item at all. Tabs and folders each
    /// reorder only among their own kind, so a folder dragged over the pinned
    /// grid resolves to no target rather than a nonsensical one.
    ///
    /// A split group is a run of tabs and reorders among tabs, but pinned tabs
    /// cannot be members, so the pinned grid refuses it the same way it refuses
    /// a folder.
    func isAccepted(by section: BrowserSidebarReorderSection) -> Bool {
        if let selection {
            if case .tabs = section { return true }
            return selection.hasFolders
        }
        return dragged.isAcceptedAlone(by: section)
    }

    /// Whether dropping the item on the open tab `tabID` may make a folder
    /// around it: the tab is not one the item carries.
    func foldsAround(_ tabID: UUID) -> Bool {
        if let selection { return !selection.ids.contains(tabID) }
        return dragged.foldsAroundAlone(tabID)
    }

    /// Whether the item may join the cards the content area for `assignment`
    /// shows. Only a tab becomes a card. A folder has no page to show, and
    /// dragging a whole group into the content area — which would have to
    /// mean "present these four instead of those" — is not a gesture this
    /// release defines. A split joins the cards on show as one block, as a
    /// selection of it does. Splits never span Spaces, so a lift from
    /// elsewhere is refused here rather than relocated first.
    func joinsCards(shownIn assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        if selection != nil { return true }
        return dragged.joinsCardsAlone(shownIn: assignment)
    }
}

/// Identity for a reorderable row, so one registry can hold tabs, folders, and
/// split groups.
enum BrowserSidebarReorderItemID: Hashable, Sendable {
    case tab(UUID)
    case folder(UUID)
    case splitGroup(UUID)

    // MARK: - Variables

    var folderID: UUID? {
        guard case .folder(let id) = self else { return nil }
        return id
    }

    var tabID: UUID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }

    // MARK: - Actions - Dropping

    /// The tab a drop anchored on this row lands in front of, in `space`. A
    /// split row stands for its whole run, so anchoring on one lands before
    /// its first member the lift does not hold, `lifted`, and a folder before
    /// its first tab.
    @MainActor
    func anchorTabID(in space: SpaceModel, lifted: Set<UUID>) -> UUID? {
        switch self {
        case .tab(let tabID):
            tabID
        case .splitGroup(let groupID):
            space.splitMembers(of: groupID).first { !lifted.contains($0.id) }?.id
        case .folder(let folderID):
            space.tabIDs(inFolder: folderID).first { !lifted.contains($0) }
        }
    }
}
