import Foundation

extension SessionTabs {
    mutating func file(
        _ selection: SessionSelection, at placement: TabPlacement, folder: UUID?, before: UUID?, beforeFolder: UUID?,
        leavesSplits: Bool, now: Date
    ) throws {
        if selection.holdsFolders {
            try fileRoots(
                selection, placement: placement, folder: folder, before: before, beforeFolder: beforeFolder,
                leavesSplits: leavesSplits, now: now)
            return
        }
        if let before, selection.holds(before) { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        if placement.holdsFolders {
            let moving = try splitRuns(selection.memberIDs, leavesSplits: leavesSplits)
            try order(moving)
            try file(
                moving, at: placement, folder: folder, now: now, before: before, beforeFolder: beforeFolder,
                detachesSplitMembers: leavesSplits)
            return
        }
        if !placement.holdsSplits && !leavesSplits,
            let member = selection.members.first(where: { $0.splitGroupID != nil })
        {
            throw Rejection.cannotPinSplit(CannotPinSplit(tabID: member.id))
        }
        try Self.requireRoom(
            placement,
            count: tabs.filter { $0.placement == placement && !selection.holds($0.id) }.count + selection.members.count)
        guard folder == nil && beforeFolder == nil,
            before == nil || tabs.contains(where: { $0.id == before && $0.placement == placement })
        else {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        for id in selection.memberIDs {
            try move(id, to: placement, folder: nil, before: before, detachSplit: leavesSplits, at: now)
        }
    }
    mutating func folder(
        _ selection: SessionSelection, placement: TabPlacement, title: String, color: BrandColor, ids: () -> UUID,
        now: Date
    ) throws -> UUID {
        try requireWholeSplits(selection)
        if selection.holdsFolders {
            let made = try makeFolder(placement: placement, title: title, color: color, ids: ids)
            try fileRoots(
                selection, placement: placement, folder: made, before: nil, beforeFolder: nil, leavesSplits: false,
                now: now)
            return made
        }
        try order(selection.memberIDs)
        let made = try makeFolder(placement: placement, title: title, color: color, ids: ids)
        try file(selection.memberIDs, at: placement, folder: made, now: now)
        return made
    }
    mutating func folder(
        _ selection: SessionSelection, around id: UUID, title: String, color: BrandColor, ids: () -> UUID, now: Date
    ) throws -> UUID {
        try requireSelectedTabs(selection)
        guard !selection.holds(id) else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        let target = try tab(id)
        guard !target.placement.isDurable, target.folderID == nil, target.splitGroupID == nil, !Self.isStartPage(target)
        else {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        let wrapped = [id] + selection.memberIDs
        try order(wrapped)
        let made = try makeFolder(placement: .current, title: title, color: color, ids: ids)
        try file(wrapped, at: .current, folder: made, now: now)
        return made
    }
    private mutating func makeFolder(placement: TabPlacement, title: String, color: BrandColor, ids: () -> UUID) throws
        -> UUID
    {
        let id = ids()
        try addFolder(id, name: title, location: placement)
        try colorFolder(id, color: color)
        return id
    }
    private mutating func fileRoots(
        _ selection: SessionSelection, placement: TabPlacement, folder: UUID?, before: UUID?, beforeFolder: UUID?,
        leavesSplits: Bool, now: Date
    ) throws {
        if let folder, selection.folders.contains(folder) { throw Rejection.folderCycle(FolderCycle(folderID: folder)) }
        guard placement.holdsFolders, before.map({ !selection.holds($0) }) ?? true,
            beforeFolder.map({ !selection.folders.contains($0) }) ?? true
        else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        if let folder, try self.folder(folder).location != placement {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        if let beforeFolder {
            let sibling = try self.folder(beforeFolder)
            guard sibling.parentID == folder && sibling.location == placement else {
                throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
            }
        } else if let before {
            let anchor = try tab(before)
            guard anchor.folderID == folder, anchor.placement == placement, try splitMembers(before)[0].id == before
            else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        }
        var blocks: [(root: SessionSelection.Root, tabs: [UUID])] = []
        var included: Set<UUID> = []
        for root in selection.roots {
            if root.isFolder {
                blocks.append((root, []))
            } else if !included.contains(root.id) {
                let members = try splitRuns([root.id], leavesSplits: leavesSplits)
                included.formUnion(members)
                blocks.append((root, members))
            }
        }
        var tabAnchor = before
        var folderAnchor = beforeFolder
        for block in blocks.reversed() {
            if block.root.isFolder {
                try moveFolder(
                    block.root.id, location: placement, parent: folder, at: now, beforeFolder: folderAnchor,
                    beforeTab: tabAnchor)
                folderAnchor = block.root.id
                tabAnchor = nil
            } else {
                try file(
                    block.tabs, at: placement, folder: folder, now: now, before: tabAnchor, beforeFolder: folderAnchor,
                    detachesSplitMembers: leavesSplits)
                tabAnchor = block.tabs[0]
                folderAnchor = nil
            }
        }
    }
}
