import Foundation

extension SessionTabs {
    struct Copy: Equatable {
        let source: UUID
        let copy: UUID
    }
    struct Join {
        let selected: UUID
        let copies: [Copy]
    }

    private static func copy(_ source: TabState.Seed, id: UUID, now: Date) -> TabState.Seed {
        var value = source
        value.id = id
        value.placement = .current
        value.folderID = nil
        value.splitGroupID = nil
        value.savedURL = nil
        value.lastActivatedAt = now
        value.positionModifiedAt = timestamp(now)
        value.titleModifiedAt = source.customTitle == nil ? nil : timestamp(now)
        return value
    }
    @discardableResult
    mutating func duplicate(
        _ id: UUID, ids: () -> UUID, at now: Date, placement: TabPlacement = .current, index: Int? = nil
    ) throws -> TabState.Seed {
        let source = try tab(id)
        guard tabs.count < Self.maximumTabs else {
            throw Rejection.tabLimitReached(TabLimitReached(limit: Self.maximumTabs))
        }
        var value = Self.copy(source, id: ids(), now: now)
        Self.place(&value, at: placement, folder: nil, now: now)
        try insert(value, at: index, duplicate: true)
        return value
    }
    mutating func join(_ id: UUID, to targetID: UUID, index: Int? = nil, ids: () -> UUID, at now: Date) throws -> Join {
        let source = try tab(id)
        let target = try tab(targetID)
        guard id != targetID else { throw Rejection.alreadyInSplit(AlreadyInSplit(tabID: id)) }
        guard !Self.isStartPage(source), !Self.isStartPage(target) else {
            throw Rejection.webPagesOnly(WebPagesOnly(tabID: Self.isStartPage(source) ? id : targetID))
        }
        let targetMembers = try splitMembers(targetID)
        let sameGroup = targetMembers.contains { $0.id == id }
        if sameGroup && index == nil { throw Rejection.alreadyInSplit(AlreadyInSplit(tabID: id)) }
        if !sameGroup && targetMembers.count >= Self.maximumSplitMembers {
            throw Rejection.splitLimitReached(SplitLimitReached(limit: Self.maximumSplitMembers))
        }
        let copyTarget = target.placement.isDurable && !sameGroup
        let copySource = source.placement.isDurable && !sameGroup
        let count = (copyTarget ? targetMembers.count : 0) + (copySource ? 1 : 0)
        guard tabs.count + count <= Self.maximumTabs else {
            throw Rejection.tabLimitReached(TabLimitReached(limit: Self.maximumTabs))
        }
        var copies: [Copy] = []
        var members: [TabState.Seed] = []
        var joiner = source
        for member in targetMembers {
            let value = copyTarget ? Self.copy(member, id: ids(), now: now) : member
            if copyTarget { copies.append(Copy(source: member.id, copy: value.id)) }
            if member.id == id { joiner = value } else { members.append(value) }
        }
        if copySource {
            joiner = Self.copy(source, id: ids(), now: now)
            copies.append(Copy(source: id, copy: joiner.id))
        }
        members.insert(joiner, at: min(max(index ?? members.count, 0), members.count))
        let group = copyTarget ? ids() : target.splitGroupID ?? ids()
        let folder = copyTarget ? nil : target.folderID
        let moving = Set(members.map(\.id))
        let ordered = try SessionFolders(folders).preservingOrder(removing: moving, tabs: tabs)
        var remaining = tabs.filter { !moving.contains($0.id) }
        let insertion: Int
        if copyTarget {
            insertion = remaining.firstIndex { !$0.placement.isDurable } ?? remaining.count
        } else {
            let first = tabs.firstIndex { $0.id == targetMembers[0].id }!
            insertion = tabs.prefix(first).filter { !moving.contains($0.id) }.count
        }
        for index in members.indices {
            Self.place(
                &members[index], at: copyTarget ? .current : target.placement, folder: folder, now: now,
                preservesSplit: true)
            members[index].splitGroupID = group
            members[index].positionModifiedAt = Self.timestamp(now)
        }
        remaining.insert(contentsOf: members, at: insertion)
        tabs = remaining
        folders = ordered
        normalizeSplits(at: now)
        return Join(selected: joiner.id, copies: copies)
    }
    @discardableResult
    mutating func joinInPlace(_ id: UUID, to targetID: UUID, index: Int?, group newGroup: UUID, at now: Date) throws
        -> Bool
    {
        guard id != targetID else { throw Rejection.alreadyInSplit(AlreadyInSplit(tabID: id)) }
        let source = try tab(id)
        let target = try tab(targetID)
        guard target.placement.holdsSplits else { throw Rejection.cannotPinSplit(CannotPinSplit(tabID: targetID)) }
        let run = try splitMembers(targetID)
        let members = run.filter { $0.id != id }
        guard members.count < Self.maximumSplitMembers else {
            throw Rejection.splitLimitReached(SplitLimitReached(limit: Self.maximumSplitMembers))
        }
        let slot = min(max(index ?? members.count, 0), members.count)
        let last = tabs.firstIndex { $0.id == run.last!.id }!
        let anchor = slot < members.count ? members[slot].id : tabs.dropFirst(last + 1).first { $0.id != id }?.id
        let group = target.splitGroupID ?? newGroup
        try move(
            id, to: target.placement, folder: target.folderID, before: anchor,
            detachSplit: source.splitGroupID != nil && source.splitGroupID != target.splitGroupID, at: now)
        for member in members.map(\.id) + [id] {
            try edit(member) {
                $0.splitGroupID = group
                $0.positionModifiedAt = Self.timestamp(now)
            }
        }
        normalizeSplits(at: now)
        return true
    }
    mutating func leaveSplit(_ id: UUID, at now: Date) throws {
        let value = try tab(id)
        guard value.splitGroupID != nil else { return }
        let members = try splitMembers(id)
        if members.count > 2 && members.last!.id != id {
            tabs.removeAll { $0.id == id }
            tabs.insert(value, at: tabs.firstIndex { $0.id == members.last!.id }! + 1)
        }
        try edit(id) {
            $0.splitGroupID = nil
            $0.positionModifiedAt = Self.timestamp(now)
        }
        normalizeSplits(at: now)
    }
    @discardableResult
    mutating func moveSplitMember(_ id: UUID, to requested: Int, at now: Date) throws -> Bool {
        let value = try tab(id)
        let run = try splitMembers(id)
        guard run.count >= 2 else { return false }
        let insertion = tabs.firstIndex { $0.id == run[0].id }! + min(max(requested, 0), run.count - 1)
        let original = Dictionary(
            uniqueKeysWithValues: run.map { member in (member.id, tabs.firstIndex { $0.id == member.id }!) })
        if tabs.firstIndex(where: { $0.id == id }) == insertion { return false }
        tabs.removeAll { $0.id == id }
        tabs.insert(value, at: insertion)
        for index in tabs.indices {
            if let before = original[tabs[index].id], before != index {
                tabs[index].positionModifiedAt = Self.timestamp(now)
            }
        }
        return true
    }
    @discardableResult
    mutating func stepSplitMember(_ id: UUID, offset: Int, at now: Date) throws -> Bool {
        let run = try splitMembers(id)
        let current = run.firstIndex { $0.id == id }!
        let (destination, overflow) = current.addingReportingOverflow(offset)
        guard offset != 0, !overflow, run.indices.contains(destination) else { return false }
        return try moveSplitMember(id, to: destination, at: now)
    }
    @discardableResult
    mutating func dissolveSplit(_ id: UUID, at now: Date) -> Bool {
        var changed = false
        for index in tabs.indices where tabs[index].splitGroupID == id {
            tabs[index].splitGroupID = nil
            tabs[index].positionModifiedAt = Self.timestamp(now)
            changed = true
        }
        return changed
    }
}
