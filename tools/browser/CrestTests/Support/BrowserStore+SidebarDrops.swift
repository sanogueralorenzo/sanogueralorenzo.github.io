import Foundation

@testable import Crest

extension BrowserStore {
    /// What the sidebar captures of `items`, picked in the Space the window
    /// shows, as the core previews it.
    func capturedSelection(_ items: [BrowserSelectionItemID]) -> BrowserCapturedSelection? {
        BrowserSidebarSelection.capture(items, in: self)
    }

    /// What the sidebar captures of the tabs `ids`, picked in the Space the
    /// window shows.
    func capturedSelection(ids: [UUID]) -> BrowserCapturedSelection? {
        capturedSelection(ids.map(BrowserSelectionItemID.tab))
    }

    /// Where the core would let `item` land, asked as the sidebar asks it
    /// when a lift begins.
    func liftPlan(
        for item: BrowserSidebarReorderItem, spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController()
    ) -> BrowserSidebarLiftPlan? {
        BrowserSidebarReorderContext(browser: self, spaceAccess: spaceAccess, state: BrowserSidebarReorderState())
            .plan(for: item)
    }

    /// Drops `item` on `target` as the sidebar does: plans the lift as it
    /// begins, then commits the drop. Answers whether the core took it.
    @discardableResult
    func sidebarDrop(
        _ item: BrowserSidebarReorderItem, on target: BrowserSidebarReorderTarget.Kind,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController()
    ) -> Bool {
        guard let plan = liftPlan(for: item, spaceAccess: spaceAccess) else { return false }
        return BrowserSidebarDropCommit(browser: self)
            .commit(BrowserSidebarReorderTarget(kind: target), for: item, plan: plan)
    }
}

/// Drops lifts as the sidebar does, planning each as it begins and then
/// committing it, for tests that drop several lifts in one window.
@MainActor
struct BrowserSidebarTestDrops {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// Drops `item` on `target`, and answers whether the core took it.
    @discardableResult
    func apply(_ target: BrowserSidebarReorderTarget, for item: BrowserSidebarReorderItem) -> Bool {
        browser.sidebarDrop(item, on: target.kind, spaceAccess: spaceAccess)
    }
}
