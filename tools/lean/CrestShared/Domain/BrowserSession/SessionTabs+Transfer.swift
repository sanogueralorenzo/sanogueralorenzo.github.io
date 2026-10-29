import Foundation

extension SessionTabs {
    /// Moves the stored tab value between Spaces; page handover happens after commit.
    @discardableResult
    mutating func transfer(
        _ id: UUID, to destination: inout SessionTabs, selected: UUID?, fallback: UUID?,
        placement requested: TabPlacement?, folder: UUID?, before: UUID?, afterSelection: Bool,
        destinationSelection: UUID?, at now: Date
    ) throws -> UUID? {
        var value = try tab(id)
        guard !destination.tabs.contains(where: { $0.id == id }),
            !destination.archived.contains(where: { $0.tab.id == id })
        else {
            throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: id))
        }
        guard destination.tabs.count < Self.maximumTabs else {
            throw Rejection.tabLimitReached(TabLimitReached(limit: Self.maximumTabs))
        }
        let placement = requested ?? value.placement
        if let folder, try destination.folder(folder).location != placement || !placement.holdsFolders {
            throw Rejection.invalidFolderPlacement(InvalidFolderPlacement())
        }
        try Self.requireRoom(placement, count: destination.tabs.filter { $0.placement == placement }.count + 1)
        guard before != id else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
        func matches(_ value: TabState.Seed) -> Bool { value.placement == placement && value.folderID == folder }
        var insertion =
            before.flatMap { anchor in destination.tabs.firstIndex { $0.id == anchor && matches($0) } }
            ?? destination.tabs.lastIndex(where: matches).map { $0 + 1 } ?? nextSection(destination.tabs, placement)
        if afterSelection, let origin = destination.tabs.firstIndex(where: { $0.id == destinationSelection }) {
            insertion = origin + 1
            if let group = destination.tabs[origin].splitGroupID {
                while insertion < destination.tabs.count && destination.tabs[insertion].splitGroupID == group {
                    insertion += 1
                }
            }
        }
        let ordered = try SessionFolders(folders).preservingOrder(removing: [id], tabs: tabs)
        tabs.removeAll { $0.id == id }
        folders = ordered
        Self.place(&value, at: placement, folder: folder, now: now)
        value.splitGroupID = nil
        value.positionModifiedAt = Self.timestamp(now)
        destination.tabs.insert(value, at: insertion)
        if afterSelection { normalizeSplits(at: now) } else { repairSplits() }
        destination.repairSplits()
        return selected == id ? tabs.contains(where: { $0.id == fallback }) ? fallback : nil : selected
    }
}
