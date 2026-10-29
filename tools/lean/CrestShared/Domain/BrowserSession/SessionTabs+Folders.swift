import Foundation

extension SessionTabs {
    private static func folderName(_ name: String) throws -> String {
        let value = BrowserAddress.trimmed(name)
        guard value.utf16.count <= maximumNameLength else {
            throw Rejection.invalidName(InvalidName(limit: maximumNameLength))
        }
        return value.isEmpty ? "Untitled Folder" : value
    }
    mutating func addFolder(_ id: UUID, name: String, location: TabPlacement = .saved, parent: UUID? = nil) throws {
        let tree = SessionFolders(folders)
        guard folders.count < SessionFolders.maximumCount else {
            throw Rejection.folderLimitReached(FolderLimitReached(limit: SessionFolders.maximumCount))
        }
        guard !folders.contains(where: { $0.id == id }) else {
            throw Rejection.folderAlreadyExists(FolderAlreadyExists(folderID: id))
        }
        guard location.holdsFolders else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        var location = location
        var insertion = folders.count
        if let parent {
            location = try folder(parent).location
            guard try tree.depth(parent) + 1 < FolderState.maximumDepth else {
                throw Rejection.folderDepthLimitReached(FolderDepthLimitReached(limit: FolderState.maximumDepth))
            }
            let subtree = try tree.subtree(parent)
            insertion = folders.lastIndex { subtree.contains($0.id) }! + 1
        }
        folders.insert(
            FolderState.Seed(id: id, title: try Self.folderName(name), location: location, parentID: parent),
            at: insertion)
    }
    mutating func renameFolder(_ id: UUID, name: String) throws {
        _ = try folder(id)
        let name = try Self.folderName(name)
        folders[folders.firstIndex { $0.id == id }!].title = name
    }
    mutating func collapseFolder(_ id: UUID, collapsed: Bool, at now: Date) throws {
        let value = try folder(id)
        guard value.isCollapsed != collapsed else { return }
        let index = folders.firstIndex { $0.id == id }!
        folders[index].isCollapsed = collapsed
        folders[index].collapseModifiedAt = now
    }
    @discardableResult
    mutating func colorFolder(_ id: UUID, color: BrandColor) throws -> Bool {
        let value = try folder(id)
        guard value.color != color else { return false }
        folders[folders.firstIndex { $0.id == id }!].color = color
        return true
    }
    @discardableResult
    mutating func deleteFolder(_ id: UUID, at now: Date) throws -> [FolderState.Seed] {
        let removing = try SessionFolders(folders).subtree(id)
        let deleted = folders.filter { removing.contains($0.id) }
        let members = tabs.filter { $0.folderID.map(removing.contains) == true }.map(\.id)
        try dismiss(
            members, selected: nil, fallback: nil, at: now, deleting: true, ensuresSelection: false,
            resetsPlacement: true)
        folders.removeAll { removing.contains($0.id) }
        return deleted
    }
    private static func validateInsertion(_ remaining: [TabState.Seed], _ insertion: Int) throws {
        if insertion > 0 && insertion < remaining.count, let split = remaining[insertion].splitGroupID,
            remaining[insertion - 1].splitGroupID == split
        {
            throw Rejection.splitBoundary(SplitBoundary())
        }
    }
    private func sectionEnd(_ values: [TabState.Seed], _ location: TabPlacement) -> Int {
        values.lastIndex { $0.placement == location }.map { $0 + 1 } ?? nextSection(values, location)
    }
    mutating func file(
        _ requested: [UUID], at location: TabPlacement, folder: UUID?, now: Date, before: UUID? = nil,
        beforeFolder: UUID? = nil, detachesSplitMembers: Bool = false
    ) throws {
        guard !requested.isEmpty, location.holdsFolders else {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        for id in requested { _ = try tab(id) }
        let tree = SessionFolders(folders)
        if let folder, try self.folder(folder).location != location {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        if let beforeFolder {
            let sibling = try self.folder(beforeFolder)
            guard sibling.parentID == folder && sibling.location == location else {
                throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
            }
        }
        let selected = Set(requested)
        let splits =
            detachesSplitMembers ? [] : Set(tabs.filter { selected.contains($0.id) }.compactMap(\.splitGroupID))
        var members = tabs.filter { selected.contains($0.id) || $0.splitGroupID.map(splits.contains) == true }
        let memberIDs = Set(members.map(\.id))
        var remaining = tabs.filter { !memberIDs.contains($0.id) }
        var nextFolders = try tree.preservingOrder(removing: memberIDs, tabs: tabs)
        let remainingTree = SessionFolders(nextFolders)
        let anchor = try beforeFolder.map { try remainingTree.tabAnchor($0, tabs: remaining) } ?? before
        if let anchor,
            memberIDs.contains(anchor) || !remaining.contains(where: { $0.id == anchor && $0.placement == location })
        {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        let predecessors = try remainingTree.emptyPredecessors(
            before: beforeFolder, anchor: anchor, parent: folder, placement: location, tabs: remaining)
        var insertion: Int
        if let anchor {
            insertion = remaining.firstIndex { $0.id == anchor }!
        } else if folder != nil, let last = remaining.lastIndex(where: { $0.folderID == folder }) {
            insertion = last + 1
        } else {
            insertion =
                folder == nil
                ? sectionEnd(remaining, location) : min(tabs.firstIndex { memberIDs.contains($0.id) }!, remaining.count)
        }
        if detachesSplitMembers && anchor == nil && insertion > 0 && insertion < remaining.count,
            let crossing = remaining[insertion].splitGroupID, remaining[insertion - 1].splitGroupID == crossing
        {
            while insertion < remaining.count && remaining[insertion].splitGroupID == crossing { insertion += 1 }
        }
        try Self.validateInsertion(remaining, insertion)
        for index in nextFolders.indices where predecessors.contains(nextFolders[index].id) {
            nextFolders[index].orderAnchorTabID = members[0].id
        }
        for index in members.indices {
            Self.place(&members[index], at: location, folder: folder, now: now, preservesSplit: !detachesSplitMembers)
            if detachesSplitMembers { members[index].splitGroupID = nil }
            members[index].positionModifiedAt = Self.timestamp(now)
        }
        remaining.insert(contentsOf: members, at: insertion)
        tabs = remaining
        folders = nextFolders
        if detachesSplitMembers { normalizeSplits(at: now) }
    }
    mutating func moveFolder(
        _ id: UUID, location: TabPlacement?, parent: UUID?, at now: Date, beforeFolder: UUID? = nil,
        beforeTab: UUID? = nil
    ) throws {
        let tree = SessionFolders(folders)
        let source = try folder(id)
        if let parent { _ = try folder(parent) }
        let movingIDs = try tree.subtree(id)
        if let parent, movingIDs.contains(parent) { throw Rejection.folderCycle(FolderCycle(folderID: id)) }
        let destinationDepth = try parent.map { try tree.depth($0) + 1 } ?? 0
        let subtreeDepth = try movingIDs.map(tree.depth).max()! - tree.depth(id)
        guard destinationDepth + subtreeDepth < FolderState.maximumDepth else {
            throw Rejection.folderDepthLimitReached(FolderDepthLimitReached(limit: FolderState.maximumDepth))
        }
        let destination = try parent.map { try folder($0).location } ?? location ?? source.location
        guard destination.holdsFolders,
            destination == .saved || !folders.contains(where: { movingIDs.contains($0.id) && $0.source != nil })
        else {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        if let beforeFolder {
            let sibling = try folder(beforeFolder)
            guard !movingIDs.contains(beforeFolder), sibling.parentID == parent, sibling.location == destination else {
                throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
            }
        }
        var members = tabs.filter { $0.folderID.map(movingIDs.contains) == true }
        let memberIDs = Set(members.map(\.id))
        if let beforeTab,
            memberIDs.contains(beforeTab)
                || !tabs.contains(where: { $0.id == beforeTab && $0.placement == destination })
        {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        var nextFolders = try tree.preservingOrder(removing: memberIDs, tabs: tabs, excluding: movingIDs)
        var remaining = tabs.filter { !memberIDs.contains($0.id) }
        let remainingTree = SessionFolders(nextFolders)
        let anchor = try beforeFolder.map { try remainingTree.tabAnchor($0, tabs: remaining) } ?? beforeTab
        let predecessors = try remainingTree.emptyPredecessors(
            before: beforeFolder, anchor: anchor, parent: parent, placement: destination, tabs: remaining)
        let moving = nextFolders.filter { movingIDs.contains($0.id) }.map { value in
            var value = value
            value.location = destination
            if value.id == id {
                value.parentID = parent
                value.orderAnchorTabID = anchor
            }
            return value
        }
        nextFolders.removeAll { movingIDs.contains($0.id) }
        let folderInsertion: Int
        if let beforeFolder {
            folderInsertion = nextFolders.firstIndex { $0.id == beforeFolder }!
        } else if let parent {
            let held = try tree.subtree(parent)
            folderInsertion = nextFolders.lastIndex { held.contains($0.id) }! + 1
        } else {
            folderInsertion = nextFolders.count
        }
        nextFolders.insert(contentsOf: moving, at: folderInsertion)
        nextFolders = try SessionFolders(nextFolders).displayOrder()
        let insertion: Int
        if let anchor, let at = remaining.firstIndex(where: { $0.id == anchor }) {
            insertion = at
        } else if let parent {
            let held = try tree.subtree(parent)
            insertion =
                remaining.lastIndex { $0.folderID.map(held.contains) == true }.map { $0 + 1 }
                ?? sectionEnd(remaining, destination)
        } else {
            insertion = sectionEnd(remaining, destination)
        }
        try Self.validateInsertion(remaining, insertion)
        for index in members.indices {
            let folder = members[index].folderID
            Self.place(&members[index], at: destination, folder: folder, now: now, preservesSplit: true)
            members[index].positionModifiedAt = Self.timestamp(now)
        }
        remaining.insert(contentsOf: members, at: insertion)
        if let first = members.first {
            for index in nextFolders.indices
            where predecessors.contains(nextFolders[index].id) && !movingIDs.contains(nextFolders[index].id) {
                nextFolders[index].orderAnchorTabID = first.id
            }
        }
        tabs = remaining
        folders = nextFolders
    }
}
