import Foundation

extension BrowserStore {
    /// Crest creates the folder and files its items in one validated edit.
    /// The around-tab form replaces that root row and keeps it first inside.
    @discardableResult
    func createSidebarFolder(
        containing payload: BrowserDragPayload, placement: BrowserTab.Placement, around tabID: UUID? = nil
    ) -> UUID? {
        guard !isClosed, payload.spaceID == activeSpace.id, placement != .pinned else { return nil }
        guard activeSpace.folders.count < 4096 else {
            showNotice(BrowserFolderFailure.limit.localizedDescription)
            return nil
        }
        if let tabID {
            guard placement == .current, canCreateCurrentFolder(around: tabID, from: payload) else { return nil }
        }
        var folder = BrowserFolder()
        folder.placement = placement
        let selection = BrowserDragPayload(
            kind: payload.kind, spaceID: payload.spaceID,
            ids: (tabID.map { [$0] } ?? []) + payload.ids, folderIDs: payload.folderIDs,
            activeTabID: payload.activeTabID)
        guard
            moveSidebarItems(
                selection, to: payload.spaceID, parentID: folder.id, placement: placement,
                creating: folder, around: tabID)
        else {
            showNotice("These items cannot be moved into a new folder.")
            return nil
        }
        editingFolderID = folder.id
        return folder.id
    }

    func canCreateCurrentFolder(around tabID: UUID, from payload: BrowserDragPayload) -> Bool {
        guard !isClosed, payload.kind == .tabs, payload.folderIDs.isEmpty, !payload.ids.isEmpty,
            !payload.ids.contains(tabID),
            let space = session.spaces.first(where: { $0.id == payload.spaceID }), space.folders.count < 4096,
            let target = space.tabs.first(where: { $0.id == tabID }), target.placement == .current,
            target.folderID == nil, !target.isSettings, target.url != nil,
            !space.splits.contains(where: { $0.tabIDs.contains(tabID) })
        else { return false }
        let ids = Set(payload.ids)
        let tabs = space.tabs.filter { ids.contains($0.id) }
        return tabs.count == ids.count && tabs.allSatisfy { !$0.isSettings }
    }

    @discardableResult
    func addFolder(parentID: UUID? = nil, github: Bool = false, in spaceID: UUID? = nil) -> UUID? {
        guard !isClosed else { return nil }
        do {
            let id = try owner.addFolder(parentID: parentID, github: github, in: spaceID ?? activeSpace.id)
            if !github { editingFolderID = id }
            return id
        } catch {
            showNotice(error.localizedDescription)
            return nil
        }
    }

    func updateFolder(_ id: UUID, change: (inout BrowserFolder) -> Void) {
        let index = spaceIndex(activeSpace.id)
        guard let position = session.spaces[index].folders.firstIndex(where: { $0.id == id }) else { return }
        change(&session.spaces[index].folders[position])
        session.spaces[index].folders[position].title = String(
            session.spaces[index].folders[position].title.prefix(256))
        changed()
    }

    func deleteFolder(_ id: UUID) {
        requestDeleteSidebarItems([], folders: [id], in: activeSpace.id)
    }

    func descendants(_ id: UUID, in space: BrowserSpace) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        while true {
            let more = Set(space.folders.filter { $0.parentID.map { ids.contains($0) } ?? false }.map(\.id))
            let count = ids.count
            ids.formUnion(more)
            if ids.count == count { return ids }
        }
    }

    func moveFolderLocally(
        _ id: UUID, into parentID: UUID?, placement: BrowserTab.Placement? = nil, before: UUID? = nil
    ) {
        moveSidebarItems(
            BrowserDragPayload(
                kind: .folder, spaceID: activeSpace.id, ids: [], folderIDs: [id], activeTabID: selectedTab?.id),
            to: activeSpace.id, parentID: parentID, placement: placement, before: before)
    }
}

extension BrowserSessionOwner {
    @discardableResult
    func addFolder(parentID: UUID? = nil, github: Bool = false, in spaceID: UUID) throws -> UUID {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw BrowserFolderFailure.space
        }
        let space = session.spaces[index]
        if github {
            guard !space.isPrivate else {
                throw BrowserFolderFailure.privateSpace
            }
            if let existing = space.folders.first(where: { $0.kind == .github }) { return existing.id }
        }
        if let parentID, !space.folders.contains(where: { $0.id == parentID && $0.kind == .regular }) {
            throw BrowserFolderFailure.parent
        }
        var folder = BrowserFolder()
        folder.parentID = parentID
        folder.placement = parentID.flatMap { id in space.folders.first { $0.id == id }?.placement }
        if github {
            guard folder.placement == nil || folder.placement == .saved else {
                throw BrowserFolderFailure.placement
            }
            folder.kind = .github
            folder.title = "GitHub"
        }
        var candidate = session
        candidate.spaces[index].folders.append(folder)
        if github { candidate.spaces[index].githubDismissed = false }
        guard (try? candidate.validate()) != nil else {
            throw BrowserFolderFailure.limit
        }
        session = candidate
        changed()
        return folder.id
    }
}

private enum BrowserFolderFailure: String, LocalizedError {
    case space = "The Space is no longer available."
    case parent = "The destination folder is no longer available."
    case privateSpace = "Live folders aren’t available in private Spaces."
    case placement = "Live folders belong in Saved Tabs."
    case limit = "The folder count or nesting limit has been reached."

    var errorDescription: String? { rawValue }
}
