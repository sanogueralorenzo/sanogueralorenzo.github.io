import Foundation

/// Commits a sidebar drop as the core's drop intent for its target. Which
/// edit a drop makes, and every rule that refuses it, is the core's, locked
/// and departing Spaces included: this only names where the lift landed, and
/// shows the person a refusal's own words.
@MainActor
struct BrowserSidebarDropCommit {
    // MARK: - Variables

    let browser: BrowserStore

    // MARK: - Actions - Committing

    /// Drops `item`, lifted as `plan` holds it, on `target`, and answers
    /// whether the core took the drop. A refusal is shown in the window's
    /// selection message instead.
    @discardableResult
    func commit(
        _ target: BrowserSidebarReorderTarget, for item: BrowserSidebarReorderItem, plan: BrowserSidebarLiftPlan
    ) -> Bool {
        // The lift names its Space by profile too; a Space replaced under it
        // is not the one it was lifted from.
        let assignment = item.spaceAssignment
        guard let space = browser.spaceModel(assignment.spaceID), space.profileID == assignment.profileID,
            let drop = target.kind.drop(lifting: plan.selection, in: space, from: browser)
        else { return false }
        let sources = BrowserTabCopySources(space)
        let changes: [Change]
        do {
            changes = try browser.family.commit(drop.intent, from: browser)
        } catch {
            browser.tabMultiSelection.message = error.placementExplanation
            return false
        }
        let copies: [TabCopied] = changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == browser.family.workspaceID else { return nil }
            return copied
        }
        browser.prepareAcceptedCopies(copies, from: sources)
        if let destination = drop.following {
            let destinationAssignment = BrowserSpaceRuntimeAssignment(
                spaceID: destination.id, profileID: destination.profileID)
            browser.pendingMovedTabActivation = browser.selectedTabID(in: destination.id).map {
                BrowserTabRuntimeAssignment(
                    tabID: $0, spaceID: destinationAssignment.spaceID, profileID: destinationAssignment.profileID)
            }
            if case .tab(let tab) = item, item.selection == nil {
                browser.interactionObserver?.browserDidMoveTab(from: tab.runtimeAssignment, to: destinationAssignment)
            }
        }
        reselect(after: drop, lifted: item, copies: copies)
        return true
    }

    /// A lifted selection stays selected where it landed, its copies in place
    /// of the tabs that stayed behind; one that left the Space is let go.
    private func reselect(
        after drop: BrowserSidebarDrop, lifted item: BrowserSidebarReorderItem,
        copies: [TabCopied]
    ) {
        guard let captured = item.selection else { return }
        let selection = browser.tabMultiSelection
        if drop.leavesSpace {
            selection.clear()
            return
        }
        let copied = Dictionary(uniqueKeysWithValues: copies.map { ($0.sourceTabID, $0.copyTabID) })
        selection.selectAll(
            units: captured.rootItems.map { root in
                guard case .tab(let id) = root, let copy = copied[id] else { return [root] }
                return [.tab(copy)]
            })
    }
}
