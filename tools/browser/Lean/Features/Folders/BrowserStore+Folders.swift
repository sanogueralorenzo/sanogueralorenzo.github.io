import Foundation

extension BrowserStore {
    @discardableResult
    func addFolder(parentID: UUID? = nil, github: Bool = false, in spaceID: UUID? = nil) -> UUID {
        let index = spaceIndex(spaceID ?? activeSpace.id)
        var folder = BrowserFolder()
        folder.parentID = parentID
        folder.placement = parentID.flatMap { id in session.spaces[index].folders.first { $0.id == id }?.placement }
        if github {
            if let existing = session.spaces[index].folders.first(where: { $0.kind == .github }) { return existing.id }
            folder.kind = .github
            folder.title = "GitHub"
            session.spaces[index].githubDismissed = false
        }
        session.spaces[index].folders.append(folder)
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
        let space = activeSpace
        let ids = descendants(id, in: space)
        let tabs = space.tabs.filter { $0.folderID.map { ids.contains($0) } ?? false }.map(\.id)
        Task {
            guard await prepareTabs(tabs) else { return }
            guard let index = session.spaces.firstIndex(where: { $0.id == space.id }) else { return }
            for id in tabs { deleteTab(id) }
            if space.folders.contains(where: { ids.contains($0.id) && $0.kind == .github }) {
                session.spaces[index].githubDismissed = true
            }
            session.spaces[index].folders.removeAll { ids.contains($0.id) }
            changed()
        }
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
