import Foundation

@testable import Crest

extension BrowserStore {
    /// The lists of one Space's sidebar in this window, as the real sidebar
    /// builds them, over no page layer: every tab holds a page, and nothing
    /// unloads or pulls an icon.
    func sidebarListContext(
        for spaceID: UUID, spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        capabilities: BrowserInteractionCapabilities = BrowserInteractionCapabilities(),
        select: @escaping (UUID) -> Void = { _ in }
    ) -> BrowserSidebarListContext? {
        guard let space = spaceModel(spaceID), let window = windowModel else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let interaction = BrowserSidebarInteractionState.connected(to: self)
        let pageAccess = BrowserSidebarPageAccess(
            containsResidentPage: { _ in true }, containsResidentPageMatching: { _ in true },
            siteThemeIconAccent: { _ in nil }, residencyRevision: { 0 }, selectPages: {},
            deactivatePagePresentation: {}, unloadPage: { _, _ in }, pullFavicon: { _, _ in nil },
            downloadCenter: BrowserDownloadCenter(permissionCenter: BrowserSitePermissionCenter()))
        let tabActions = BrowserSidebarTabActions(
            assignment: assignment, browser: self, reorderState: interaction.sidebarReorderState,
            spaceAccess: spaceAccess, syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil })
        return BrowserSidebarListContext(
            space: space, window: window, favicons: core.state.favicons, browser: self, spaceAccess: spaceAccess,
            pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities, select: select)
    }
}
