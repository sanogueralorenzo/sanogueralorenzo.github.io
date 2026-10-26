import Foundation

// MARK: - Pages

extension BrowserStore {
    /// Opens a page through the core, from this window, for `tabID` in
    /// `spaceID`, or for a transient request presenting as `transient` when
    /// `tabID` is nil. A page another page opened, `opener`, runs on its
    /// opener's engine. Nil when a rule refuses it, such as a locked Space,
    /// one being deleted, or a tab that already has a page.
    func openPage(
        in spaceID: UUID, for tabID: UUID?, presenting transient: TransientPresentation? = nil, opener: UUID? = nil
    ) -> Engines.OpenedPage? {
        core.engines.open(
            OpenPage(
                pageID: UUID(), workspaceID: window.workspaceID, spaceID: spaceID, tabID: tabID,
                windowID: windowID, transient: tabID == nil ? transient : nil, openerPageID: opener))
    }

    /// Gives `tabID` in `spaceID` the back and forward history its archive
    /// kept, for the page it opens next. Changes nothing when a rule refuses
    /// it or the core cannot read it.
    func restoreTabHistory(_ history: Data, in spaceID: UUID, for tabID: UUID) {
        _ = try? core.send(
            RestoreTabHistory(workspaceID: window.workspaceID, spaceID: spaceID, tabID: tabID, archive: history))
    }

    /// Gives `page` to `tabID` in `spaceID` of this window's workspace, or to
    /// a transient request when `tabID` is nil, hosted by this window. False
    /// when a rule refuses it.
    func adoptPage(_ page: CorePage, in spaceID: UUID, as tabID: UUID?) -> Bool {
        page.move(to: window.workspaceID, spaceID: spaceID, tabID: tabID, windowID: windowID)
    }

    /// Whether returning `tabID` to its saved address would change anything,
    /// as the core answers it for this window: the tab is away from that
    /// page, or its page here is heading to another.
    func returnsToSavedAddress(_ tabID: UUID, in spaceID: UUID) -> Bool {
        let question = CanReturnToSavedAddress(
            workspaceID: window.workspaceID, windowID: windowID, spaceID: spaceID,
            tabID: tabID)
        return (try? core.query(question))?.changesPage ?? false
    }
}
