import Foundation

extension SessionMutations {
    func batchEdit(_ request: some SessionIntent) throws -> SessionMutation? {
        let spaceID: UUID
        let windowID: UUID
        let selection: TabSelection
        switch request {
        case let value as CloseTabs: (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as DeleteTabs: (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as DuplicateTabs:
            (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as SplitTabs: (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as SeparateSplits:
            (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as FolderTabs: (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as FolderTabsAround:
            (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        case let value as MoveTabsToSpace:
            (spaceID, windowID, selection) = (value.spaceID, value.windowID, value.selection)
        default: return nil
        }
        var (original, values, selected) = try selecting(spaceID, windowID: windowID, selection: selection)
        var followUp = window(windowID)
        let shown = followUp.window?.tab(in: spaceID)
        func fallback(_ follow: inout SessionWindowFollowUp) -> UUID? {
            guard let shown, selected.holds(shown) else { return nil }
            return follow.fallback(
                in: spaceID, dismissing: shown,
                available: Set(original.tabs.filter { !selected.holds($0.id) }.map(\.id)))
        }
        var stage = SessionMutation.Stage.batch
        var effects: [any CoreChange] = []
        var spaces: [SpaceState.Seed] = []
        switch request {
        case is CloseTabs:
            let next = try values.close(selected, shown: shown, fallback: fallback(&followUp), at: now)
            followUp.showTab(next, in: spaceID)
        case is DeleteTabs:
            let next = try values.delete(selected, shown: shown, fallback: fallback(&followUp), at: now)
            followUp.showTab(next, in: spaceID)
            stage = .batchDeletion
        case let request as DuplicateTabs:
            let copies = try values.duplicate(selected, ids: ids, at: now)
            effects = try startingCopies(copies, in: &values, appearances: request.appearances)
        case let request as SplitTabs:
            let joined = try values.split(
                selected, target: request.targetTabID, index: request.index, shown: shown, ids: ids, at: now)
            followUp.showTab(joined.shown, in: spaceID)
            effects = try startingCopies(joined.copies, in: &values, appearances: request.appearances)
        case is SeparateSplits: try values.separate(selected, at: now)
        case let request as FolderTabs:
            _ = try values.folder(
                selected, placement: request.placement, title: folderTitle(request.title),
                color: FolderState.defaultColor, ids: ids, now: now)
        case let request as FolderTabsAround:
            _ = try values.folder(
                selected, around: request.tabID, title: folderTitle(request.title), color: FolderState.defaultColor,
                ids: ids, now: now)
        case let request as MoveTabsToSpace:
            guard request.destinationSpaceID != spaceID else {
                throw Rejection.alreadyInSpace(AlreadyInSpace(spaceID: spaceID))
            }
            let destination = try space(request.destinationSpaceID)
            var receiving = try SessionTabs(destination)
            let moved = try values.move(
                selected, to: &receiving, shown: shown, fallback: fallback(&followUp),
                destinationShown: followUp.window?.tab(in: destination.id), follows: request.follows, at: now)
            followUp.showTab(moved.shown, in: spaceID)
            followUp.showTab(moved.destinationShown, in: destination.id)
            if request.follows { followUp.showSpace(destination.id) }
            spaces.append(receiving.capture(destination))
        default: preconditionFailure("Unrecognized selection edit")
        }
        return replacing([values.capture(original)] + spaces, stage: stage, followUp: followUp, effects: effects)
    }
    func move(_ request: MoveTabToSpace) throws -> SessionMutation {
        guard request.destinationSpaceID != request.spaceID else {
            throw Rejection.alreadyInSpace(AlreadyInSpace(spaceID: request.spaceID))
        }
        let original = try space(request.spaceID)
        let destination = try space(request.destinationSpaceID)
        var values = try SessionTabs(original)
        var receiving = try SessionTabs(destination)
        _ = try values.tab(request.tabID)
        var followUp = window(request.windowID)
        var shownThere = followUp.window?.tab(in: destination.id)
        let fallback = followUp.fallback(
            in: original.id, dismissing: request.tabID,
            available: Set(original.tabs.filter { $0.id != request.tabID }.map(\.id)))
        let shown = try values.transfer(
            request.tabID, to: &receiving, selected: followUp.window?.tab(in: original.id), fallback: fallback,
            placement: request.placement, folder: request.folderID, before: request.beforeTabID, afterSelection: false,
            destinationSelection: shownThere, at: now)
        if request.follows {
            try receiving.edit(request.tabID) { $0.lastActivatedAt = now }
            shownThere = request.tabID
        }
        followUp.showTab(shown, in: original.id)
        followUp.showTab(shownThere, in: destination.id)
        if request.follows { followUp.showSpace(destination.id) }
        return replacing(
            [values.capture(original), receiving.capture(destination)], stage: .transfer, followUp: followUp)
    }
}
