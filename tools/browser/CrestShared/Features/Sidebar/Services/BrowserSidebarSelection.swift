import Foundation

/// The window's sidebar selection over what the sidebar shows: the units a
/// click, a range or Select All takes, in the order the core's outline lists
/// them, and what the selected picks hold, as the core previews it.
@MainActor
enum BrowserSidebarSelection {
    // MARK: - Actions - Units

    /// The items a person can select in the Space the window shows, in the
    /// order the sidebar shows them, each unit what one click selects: a tab,
    /// a folder, or the members of a split. It follows the core's outline:
    /// pinned tabs, the saved section while it is open, then the open tabs;
    /// the inside of an open folder after its row, and the rows a collapsed
    /// folder keeps on screen: the folders on the way to its kept tab, then
    /// the tab's row. A locked Space offers none.
    static func itemUnits(in browser: BrowserStore) -> [[BrowserSelectionItemID]] {
        guard let space = browser.spaceModel(browser.selectedSpaceID) else { return [] }
        let interaction = browser.interactionObserver as? BrowserSidebarInteractionState
        if space.settings.accessPolicy == .deviceOwnerAuthentication {
            guard let access = interaction?.sidebarSpaceAccess, !access.isLocked(space) else { return [] }
        }
        var units: [[BrowserSelectionItemID]] = []
        func unit(of row: SidebarRow) -> [BrowserSelectionItemID] {
            row.kind.groupsTabs ? row.members.map(BrowserSelectionItemID.tab) : [.tab(row.id)]
        }
        func walk(_ list: SidebarListModel, keeping kept: UUID) {
            guard
                let row = list.rows.first(where: { row in
                    row.kind.opensList ? space.tabIDs(inFolder: row.id).contains(kept) : row.members.contains(kept)
                })
            else { return }
            guard row.kind.opensList else {
                units.append(unit(of: row))
                return
            }
            units.append([.folder(row.id)])
            walk(space.sidebar.inside(row.id), keeping: kept)
        }
        func walk(_ list: SidebarListModel) {
            for row in list.rows {
                guard row.kind.opensList else {
                    units.append(unit(of: row))
                    continue
                }
                units.append([.folder(row.id)])
                let inside = space.sidebar.inside(row.id)
                guard space.folders.model(row.id)?.isCollapsed == true else {
                    walk(inside)
                    continue
                }
                let kept = interaction?.collapsedFolderVisibility(
                    for: BrowserFolderRuntimeAssignment(folderID: row.id, spaceID: space.id, profileID: space.profileID)
                ).state.keptTabID
                if let kept { walk(inside, keeping: kept) }
            }
        }
        walk(space.sidebar.section(.pinned))
        if space.settings.isSavedTabsExpanded { walk(space.sidebar.section(.saved)) }
        walk(space.sidebar.section(.current))
        return units
    }

    /// The same units, of tabs alone.
    static func units(in browser: BrowserStore) -> [[UUID]] {
        itemUnits(in: browser).map { $0.compactMap(\.tabID) }.filter { !$0.isEmpty }
    }

    // MARK: - Actions - Capture

    /// What the selection holds, as the core previews it, when it holds
    /// `item`: the Space the window shows, and the picks the selection holds
    /// in sidebar order. Nil when the selection does not hold the item.
    static func capture(for item: BrowserSelectionItemID, in browser: BrowserStore) -> BrowserCapturedSelection? {
        let selection = browser.tabMultiSelection
        guard selection.contains(item) else { return nil }
        let items = itemUnits(in: browser).flatMap { $0 }.filter { selection.selectedItems.contains($0) }
        guard items.contains(item) else { return nil }
        return capture(items, in: browser)
    }

    /// What `items`, picked in the Space the window shows, hold there, as the
    /// core previews it.
    static func capture(_ items: [BrowserSelectionItemID], in browser: BrowserStore) -> BrowserCapturedSelection? {
        guard let space = browser.spaceModel(browser.selectedSpaceID),
            let selected = try? browser.core.query(
                SelectionPreview(
                    workspaceID: browser.family.workspaceID, spaceID: space.id, tabIDs: items.compactMap(\.tabID),
                    folderIDs: items.compactMap(\.folderID)))
        else { return nil }
        return BrowserCapturedSelection(
            assignment: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
            selected: selected)
    }

    // MARK: - Actions - Showing

    /// Whether a row draws itself selected for tab actions: the window's
    /// selection holds it and no selected folder around it does. Reading it
    /// observes the item's own membership, and the row's folders only while
    /// it is selected.
    static func showsSelected(_ item: BrowserSelectionItemID, in context: BrowserSidebarListContext) -> Bool {
        let selection = context.browser.tabMultiSelection
        guard selection.contains(item) else { return false }
        return !isCoveredBySelectedFolder(item, in: context.space, selection: selection)
    }

    /// Whether a selected folder holds the item, however deep.
    static func isCoveredBySelectedFolder(
        _ item: BrowserSelectionItemID, in space: SpaceModel, selection: BrowserTabMultiSelection
    ) -> Bool {
        guard selection.isEngaged else { return false }
        var parent: UUID? =
            switch item {
            case .tab(let id): space.tabs.model(id)?.folderID
            case .folder(let id): space.folders.model(id)?.parentID
            }
        var visited: Set<UUID> = []
        while let id = parent, visited.insert(id).inserted {
            if selection.contains(.folder(id)) { return true }
            parent = space.folders.model(id)?.parentID
        }
        return false
    }
}
