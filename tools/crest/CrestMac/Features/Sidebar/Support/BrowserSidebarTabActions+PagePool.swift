import Foundation

extension BrowserSidebarTabActions {
    /// Binds a Space's sidebar row actions to the window's card pool.
    ///
    /// Clearing the current tabs leaves the pool holding cards for tabs that no
    /// longer exist and no card on screen, so the windowed shell reconciles and
    /// re-presents in that order — the page it brings up is whichever one the
    /// session now points at.
    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        reorderState: BrowserSidebarReorderState,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.init(
            assignment: assignment,
            browser: browser,
            reorderState: reorderState,
            spaceAccess: spaceAccess,
            syncPagesAfterMutation: {
                pages.reconcile()
                pages.select()
            },
            pullFavicon: { tabID, assignment in
                await pages.pullFavicon(for: tabID, matching: assignment)
            }
        )
    }
}
