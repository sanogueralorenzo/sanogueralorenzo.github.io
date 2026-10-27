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
        let s = spaceIndex(activeSpace.id)
        guard let folder = activeSpace.folders.first(where: { $0.id == id }) else { return }
        let nested = descendants(id, in: activeSpace)
        guard parentID.map({ !nested.contains($0) }) ?? true,
            parentID.map({ parent in activeSpace.folders.contains { $0.id == parent && $0.kind == .regular } }) ?? true
        else { return }
        let parent = parentID.flatMap { parent in activeSpace.folders.first { $0.id == parent } }
        let location = placement ?? parent?.placement ?? folder.placement ?? .saved
        guard location != .pinned, folder.kind != .github || location == .saved else { return }
        var candidate = session
        for i in candidate.spaces[s].folders.indices where nested.contains(candidate.spaces[s].folders[i].id) {
            candidate.spaces[s].folders[i].placement = location
            if candidate.spaces[s].folders[i].id == id { candidate.spaces[s].folders[i].parentID = parentID }
        }
        for i in candidate.spaces[s].tabs.indices
        where candidate.spaces[s].tabs[i].folderID.map(nested.contains) == true {
            candidate.spaces[s].tabs[i].placement = location
            if location == .current {
                candidate.spaces[s].tabs[i].savedURL = nil
            } else if candidate.spaces[s].tabs[i].savedURL == nil {
                candidate.spaces[s].tabs[i].savedURL = candidate.spaces[s].tabs[i].url
            }
        }
        if let before, before != id,
            let index = candidate.spaces[s].folders.firstIndex(where: { $0.id == id })
        {
            let moved = candidate.spaces[s].folders.remove(at: index)
            let target = candidate.spaces[s].folders.firstIndex { $0.id == before } ?? candidate.spaces[s].folders.count
            candidate.spaces[s].folders.insert(moved, at: target)
        }
        guard (try? candidate.validate()) != nil else { return }
        session = candidate
        reorderSidebarItems([id], in: activeSpace.id, before: before)
        changed()
    }

    func moveFolder(
        _ id: UUID, from source: UUID, to destination: UUID, parentID: UUID? = nil,
        placement: BrowserTab.Placement? = nil, before: UUID? = nil
    ) {
        guard source != destination, let space = session.spaces.first(where: { $0.id == source }),
            let target = session.spaces.first(where: { $0.id == destination }),
            parentID.map({ parent in target.folders.contains { $0.id == parent && $0.kind == .regular } }) ?? true
        else { return }
        let targetPlacement =
            placement ?? parentID.flatMap { parent in target.folders.first { $0.id == parent }?.placement }
        guard targetPlacement != .pinned else { return }
        let folderIDs = descendants(id, in: space)
        let tabs = relatedTabIDs(space.tabs.filter { $0.folderID.map { folderIDs.contains($0) } ?? false }.map(\.id))
        Task {
            guard await prepareTabs(tabs) else { return }
            for id in tabs {
                await pages[id]?.captureDocumentState()
                pages[id]?.checkpointNativeState()
            }
            guard let sourceIndex = session.spaces.firstIndex(where: { $0.id == source }),
                let targetIndex = session.spaces.firstIndex(where: { $0.id == destination })
            else { return }
            let groups = session.spaces[sourceIndex].splits.filter { Set($0.tabIDs).isSubset(of: Set(tabs)) }
            if session.spaces[sourceIndex].folders.contains(where: { folderIDs.contains($0.id) && $0.kind == .github }),
                session.spaces[targetIndex].isPrivate
                    || session.spaces[targetIndex].folders.contains(where: { $0.kind == .github })
            {
                return
            }
            var folders = session.spaces[sourceIndex].folders.filter { folderIDs.contains($0.id) }
            for i in folders.indices {
                if folders[i].id == id { folders[i].parentID = parentID }
                if let targetPlacement { folders[i].placement = targetPlacement }
            }
            guard !folders.contains(where: { $0.kind == .github && $0.placement == .current }) else { return }
            var moving = session.spaces[sourceIndex].tabs.filter { tabs.contains($0.id) }
            for i in moving.indices {
                if let targetPlacement {
                    moving[i].placement = targetPlacement
                    moving[i].savedURL = targetPlacement == .current ? nil : moving[i].savedURL ?? moving[i].url
                }
            }
            session.spaces[sourceIndex].folders.removeAll { folderIDs.contains($0.id) }
            session.spaces[sourceIndex].tabs.removeAll { tabs.contains($0.id) }
            for id in tabs {
                detachFromSplits(id)
                unload(id)
            }
            session.spaces[targetIndex].folders += folders
            session.spaces[targetIndex].tabs += moving
            session.spaces[targetIndex].splits += groups
            for context in owner.contexts.values where context.windowState.spaceID == source {
                if let id = context.selectedTab?.id, tabs.contains(id) { context.setSelectedTab(nil, in: source) }
                if let old = context.windowState.tabsBySpace[source], tabs.contains(old) {
                    context.setSelectedTab(nil, in: source)
                }
            }
            reorderSidebarItems([id], in: destination, before: before)
            selectSpace(destination)
            changed()
        }
    }
}
