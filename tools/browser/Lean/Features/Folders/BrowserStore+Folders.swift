import Foundation

extension BrowserStore {
    @discardableResult
    func addFolder(parentID: UUID? = nil, github: Bool = false, in spaceID: UUID? = nil) -> UUID? {
        guard !isClosed, let index = session.spaces.firstIndex(where: { $0.id == (spaceID ?? activeSpace.id) }) else {
            return nil
        }
        let space = session.spaces[index]
        if github {
            guard !space.isPrivate else {
                showNotice("Live folders aren’t available in private Spaces.")
                return nil
            }
            if let existing = space.folders.first(where: { $0.kind == .github }) { return existing.id }
        }
        if let parentID, !space.folders.contains(where: { $0.id == parentID && $0.kind == .regular }) {
            showNotice("The destination folder is no longer available.")
            return nil
        }
        var folder = BrowserFolder()
        folder.parentID = parentID
        folder.placement = parentID.flatMap { id in space.folders.first { $0.id == id }?.placement }
        if github {
            guard folder.placement == nil || folder.placement == .saved else {
                showNotice("Live folders belong in Saved Tabs.")
                return nil
            }
            folder.kind = .github
            folder.title = "GitHub"
        }
        var candidate = session
        candidate.spaces[index].folders.append(folder)
        if github { candidate.spaces[index].githubDismissed = false }
        guard (try? candidate.validate()) != nil else {
            showNotice("The folder count or nesting limit has been reached.")
            return nil
        }
        session = candidate
        if !github { editingFolderID = folder.id }
        changed()
        return folder.id
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
