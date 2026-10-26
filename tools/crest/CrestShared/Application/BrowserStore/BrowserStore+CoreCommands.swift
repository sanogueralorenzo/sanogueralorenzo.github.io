import Foundation

// Store commands use the owned core session: they send intent and name this
// window, which the core's device moves when the command commits.
extension BrowserStore {
    /// The name a new folder takes, in the app's language.
    static var newFolderTitle: String { String(localized: "New Folder") }

    func createSessionTabFolder(
        _ tabIDs: [UUID], in spaceID: UUID,
        detachesSplitMembers: Bool
    ) -> UUID? {
        guard !tabIDs.isEmpty else { return nil }
        let id = UUID()
        let creation = CreateFolder(
            workspaceID: family.workspaceID, spaceID: spaceID, folderID: id, placement: .current,
            parentID: nil, title: nil, color: BrandColor.folderDefault,
            tabIDs: tabIDs, leavesSplits: detachesSplitMembers)
        guard family.send(creation, from: self) else { return nil }
        return spaceModel(spaceID)?.folders.contains(id) == true ? id : nil
    }

    /// Returns a saved or pinned tab to the address it belongs to, and answers
    /// whether the core accepted it, including for a tab already there.
    func returnSessionTabToSavedAddress(tabID: UUID, in spaceID: UUID) -> Bool {
        family.perform(
            ReturnToSavedAddress(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID),
            from: self) != nil
    }

    /// Opens a tab showing `content` in `placement`'s section and answers its
    /// identity, or nil when the core refused it. The core places a tab
    /// opened from `origin` after it and outside its split, resolves its
    /// address and names a page it was given no title for.
    @discardableResult
    func openSessionTab(
        _ content: TabContent, in spaceID: UUID, placement: TabPlacement = .current,
        insertingAfter origin: UUID? = nil, shouldSelect: Bool = true
    ) -> UUID? {
        let id = UUID()
        let opening = OpenTab(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: id,
            content: content, placement: placement, afterTabID: origin, shows: shouldSelect)
        return family.perform(opening, from: self) == nil ? nil : id
    }

    /// Closes a tab the way its section closes one: the core archives an open
    /// tab and puts a saved or pinned tab's page away. A window that showed it
    /// returns to the tab it showed before, which the core's device chooses.
    @discardableResult
    func closeSessionTab(_ id: UUID, in spaceID: UUID) -> Bool {
        family.perform(
            CloseTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                tabID: id),
            from: self) != nil
    }

    /// Whether closing `id` leaves only its window to close: the core keeps
    /// the Start Page that is its Space's only tab.
    func closingLeavesOnlyTheWindow(_ id: UUID, in spaceID: UUID) -> Bool {
        let closing = CloseTab(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: id)
        guard case .lastStartPage = family.refusal(of: closing, from: self) else { return false }
        return true
    }

    @discardableResult
    func deleteSessionTab(_ id: UUID, in spaceID: UUID) -> Bool {
        family.perform(
            DeleteTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                tabID: id),
            from: self) != nil
    }

    func clearSessionTabs(in spaceID: UUID) -> Bool {
        family.perform(
            ClearCurrentTabs(workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID),
            from: self) != nil
    }

    func renameSessionTab(_ title: String?, tabID: UUID, in spaceID: UUID) -> Bool {
        family.send(
            RenameTab(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID, title: title),
            from: self)
    }

    func renameSessionFolder(_ id: UUID, in spaceID: UUID, title: String) -> Bool {
        family.send(
            RenameFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id, title: title),
            from: self)
    }

    func collapseSessionFolder(_ id: UUID, in spaceID: UUID, isCollapsed: Bool) -> Bool {
        family.send(
            CollapseFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id,
                collapsed: isCollapsed),
            from: self)
    }

    func deleteSessionFolder(_ id: UUID, in spaceID: UUID) -> Bool {
        family.send(
            DeleteFolder(workspaceID: family.workspaceID, spaceID: spaceID, folderID: id),
            from: self)
    }

    func moveSessionFolder(
        _ id: UUID, in spaceID: UUID, into parentID: UUID?,
        before siblingID: UUID? = nil, location: BrowserFolderLocation? = nil, beforeTabID: UUID? = nil
    ) -> Bool {
        family.send(
            MoveFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id,
                placement: location?.tabPlacement, parentID: parentID, beforeFolderID: siblingID,
                beforeTabID: beforeTabID),
            from: self)
    }

    func fileSessionTabs(
        _ ids: [UUID], in spaceID: UUID, into folderID: UUID?,
        location: BrowserFolderLocation, before anchor: UUID? = nil, beforeFolderID: UUID? = nil,
        detachesSplitMembers: Bool = false
    ) -> Bool {
        family.send(
            FileTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                selection: TabSelection(tabIDs: ids, folderIDs: [], memberTabIDs: ids),
                placement: location.tabPlacement, folderID: folderID, beforeTabID: anchor,
                beforeFolderID: beforeFolderID, leavesSplits: detachesSplitMembers),
            from: self)
    }
}
