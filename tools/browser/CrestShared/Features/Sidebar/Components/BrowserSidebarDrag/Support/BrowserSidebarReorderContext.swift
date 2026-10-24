import Foundation

/// Shared drag state and the collaborators authorized to commit its result.
@MainActor
struct BrowserSidebarReorderContext {
    // MARK: - Variables

    let state: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    // MARK: - Initializers

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, state: BrowserSidebarReorderState) {
        self.state = state
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    // MARK: - Actions - Lifting

    /// What lifting `item` carries, as the core reads a sidebar selection, and
    /// where the core would let it land, asked once as the lift begins: the
    /// window's selection when the item carries one, and otherwise the row
    /// alone — a tab, every member of a split, or a folder with all it holds.
    func plan(for item: BrowserSidebarReorderItem) -> BrowserSidebarLiftPlan? {
        let assignment = item.spaceAssignment
        let selection: TabSelection
        if let captured = item.selection {
            selection = captured.selection
        } else {
            let picks = item.rowPicks
            guard
                let selected = try? browser.core.query(
                    SelectionPreview(
                        workspaceID: browser.family.workspaceID, spaceID: assignment.spaceID, tabIDs: picks.tabIDs,
                        folderIDs: picks.folderIDs)),
                let rowSelection = item.rowSelection(from: selected)
            else { return nil }
            selection = rowSelection
        }
        let targets = try? browser.core.query(
            DropTargets(
                workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: assignment.spaceID,
                selection: selection))
        return BrowserSidebarLiftPlan(
            selection: selection, targets: targets,
            refusals: BrowserSidebarDropRefusals(browser: browser, spaceID: assignment.spaceID))
    }

    // MARK: - Actions - Dropping

    /// Commits a released lift as the core's drop intent for where it landed.
    func commit(_ drop: BrowserSidebarReorderDrop) {
        guard let plan = drop.plan ?? plan(for: drop.item) else { return }
        BrowserSidebarDropCommit(browser: browser).commit(drop.target, for: drop.item, plan: plan)
    }
}
