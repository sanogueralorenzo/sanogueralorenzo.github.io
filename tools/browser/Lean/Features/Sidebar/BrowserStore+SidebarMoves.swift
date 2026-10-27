import Foundation

extension BrowserStore {
    /// One validated edit for a selection. Local moves keep their page instances;
    /// a cross-Space move asks every affected page before changing any ownership.
    @discardableResult
    func moveSidebarItems(
        _ payload: BrowserDragPayload, to destination: UUID, parentID: UUID? = nil,
        placement: BrowserTab.Placement? = nil, before: UUID? = nil
    ) -> Bool {
        guard let source = session.spaces.first(where: { $0.id == payload.spaceID }),
            let target = session.spaces.first(where: { $0.id == destination })
        else { return false }
        let local = payload.spaceID == destination
        let targetTab = target.tabs.first { $0.id == before }
        let targetFolder = target.folders.first { $0.id == before }
        let targetParent = parentID ?? targetTab?.folderID ?? targetFolder?.parentID
        let folders = payload.folderIDs.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1, in: source)) }
        let requested = Set(payload.ids)
        let sourceTabs = Dictionary(uniqueKeysWithValues: source.tabs.map { ($0.id, $0) })
        guard requested.isSubset(of: Set(sourceTabs.keys)),
            payload.folderIDs.allSatisfy({ id in source.folders.contains { $0.id == id } })
        else { return false }
        let tabs = source.sidebarItemIDs.filter { id in
            requested.contains(id) || sourceTabs[id]?.folderID.map(folders.contains) == true
        }
        guard !tabs.isEmpty || !folders.isEmpty else { return false }
        let tabSet = Set(tabs)
        let wholeGroups = source.splits.filter { Set($0.tabIDs).isSubset(of: tabSet) }
        let roots = Set(payload.folderIDs).union(
            source.tabs.filter {
                tabSet.contains($0.id) && $0.folderID.map(folders.contains) != true
            }.map(\.id))
        let order = source.sidebarItemIDs.filter(roots.contains)
        let following = (payload.activeTabID ?? selectedTab?.id).flatMap { tabSet.contains($0) ? $0 : nil }

        let commit: @MainActor () -> Bool = { [self] in
            guard !isClosed, let s = session.spaces.firstIndex(where: { $0.id == payload.spaceID }),
                let d = session.spaces.firstIndex(where: { $0.id == destination })
            else { return false }
            let current = session.spaces[s]
            let destinationSpace = session.spaces[d]
            // A folder or split edited while its documents were answering is a
            // different unit. Never publish half of it or move newly added pages
            // that did not answer the close safeguards.
            guard payload.folderIDs.allSatisfy({ id in current.folders.contains { $0.id == id } }),
                wholeGroups.allSatisfy({ original in
                    current.splits.contains { $0.id == original.id && Set($0.tabIDs) == Set(original.tabIDs) }
                }),
                payload.folderIDs.reduce(into: Set<UUID>(), { $0.formUnion(descendants($1, in: current)) }) == folders,
                Set(
                    current.tabs.filter {
                        requested.contains($0.id) || $0.folderID.map(folders.contains) == true
                    }.map(\.id)) == tabSet,
                targetParent.map({ id in
                    !folders.contains(id) && destinationSpace.folders.contains { $0.id == id && $0.kind == .regular }
                }) ?? true,
                before.map({
                    destinationSpace.orderedSidebarIDs.contains($0) && !folders.contains($0) && !tabSet.contains($0)
                }) ?? true
            else { return false }
            let beforeTab = destinationSpace.tabs.first { $0.id == before }
            let beforeFolder = destinationSpace.folders.first { $0.id == before }
            let location =
                placement ?? beforeTab?.placement ?? beforeFolder.map { $0.placement ?? .saved }
                ?? targetParent.flatMap { id in
                    destinationSpace.folders.first { $0.id == id }.map { $0.placement ?? .saved }
                }
            let hasLiveFolder = current.folders.contains { folders.contains($0.id) && $0.kind == .github }
            guard folders.isEmpty || location != .pinned,
                !hasLiveFolder
                    || (!destinationSpace.isPrivate && location != .current
                        && !destinationSpace.folders.contains { $0.kind == .github && !folders.contains($0.id) }),
                !current.tabs.contains(where: {
                    tabSet.contains($0.id) && $0.isSettings
                        && (targetParent != nil || (location != nil && location != .current))
                })
            else { return false }

            var movingFolders = current.folders.filter { folders.contains($0.id) }
            for i in movingFolders.indices {
                if payload.folderIDs.contains(movingFolders[i].id) { movingFolders[i].parentID = targetParent }
                if let location { movingFolders[i].placement = location }
            }
            let byID = Dictionary(uniqueKeysWithValues: current.tabs.map { ($0.id, $0) })
            var moving = tabs.compactMap { byID[$0] }
            for i in moving.indices {
                if moving[i].folderID.map(folders.contains) != true { moving[i].folderID = targetParent }
                if let location { moving[i].placement = location }
                if moving[i].placement == .pinned { moving[i].folderID = nil }
                moving[i].savedURL = moving[i].placement == .current ? nil : moving[i].savedURL ?? moving[i].url
            }
            let groups = current.splits.filter { Set($0.tabIDs).isSubset(of: tabSet) }
            var candidate = session
            candidate.spaces[s].sidebarOrderIDs = current.orderedSidebarIDs.filter {
                !folders.contains($0) && !tabSet.contains($0)
            }
            candidate.spaces[s].folders.removeAll { folders.contains($0.id) }
            candidate.spaces[s].tabs.removeAll { tabSet.contains($0.id) }
            if !local {
                if current.selectedTabID.map(tabSet.contains) == true { candidate.spaces[s].selectedTabID = nil }
                for i in candidate.windows.indices
                where candidate.windows[i].tabsBySpace[payload.spaceID].map(tabSet.contains) == true {
                    candidate.windows[i].tabsBySpace[payload.spaceID] = nil
                    candidate.windows[i].emptySpaces.insert(payload.spaceID)
                }
            }
            for i in candidate.spaces[s].splits.indices {
                let group = candidate.spaces[s].splits[i]
                let kept = group.tabIDs.indices.filter { !tabSet.contains(group.tabIDs[$0]) }
                candidate.spaces[s].splits[i].tabIDs = kept.map { group.tabIDs[$0] }
                let fractions = kept.map { group.fractions[$0] }
                let total = fractions.reduce(0, +)
                candidate.spaces[s].splits[i].fractions = total > 0 ? fractions.map { $0 / total } : []
            }
            candidate.spaces[s].splits.removeAll { $0.tabIDs.count < 2 }
            candidate.spaces[d].folders += movingFolders
            candidate.spaces[d].tabs += moving
            candidate.spaces[d].splits += groups
            if hasLiveFolder && !local {
                candidate.spaces[s].githubDismissed = true
                candidate.spaces[d].githubDismissed = false
            }
            guard (try? candidate.validate()) != nil else { return false }
            let previousPages = visiblePages
            let affected = owner.contexts.values.filter {
                $0.windowState.tabsBySpace[payload.spaceID].map(tabSet.contains) == true
            }
            session = candidate
            if !local {
                for id in tabs { unload(id) }
                for context in affected { context.setSelectedTab(nil, in: payload.spaceID) }
            }
            reorderSidebarItems(order, in: destination, before: before)
            if local {
                let visible = owner.visiblePageIDs
                for page in previousPages where !visible.contains(page.id) {
                    page.lastSelected = Date()
                    page.beginPictureInPicture()
                }
            } else if let following = following ?? tabs.first {
                selectTab(following)
            } else {
                selectSpace(destination)
            }
            changed()
            if hasLiveFolder && !local { integration(for: destination).requestRefresh() }
            return true
        }
        if local { return commit() }
        Task {
            guard !isClosed, await prepareTabs(tabs) else { return }
            for id in tabs {
                await pages[id]?.captureDocumentState()
                pages[id]?.checkpointNativeState()
            }
            _ = commit()
        }
        return true
    }
}
