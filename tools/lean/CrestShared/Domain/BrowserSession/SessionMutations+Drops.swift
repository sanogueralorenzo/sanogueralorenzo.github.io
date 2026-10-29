import Foundation

extension SessionMutations {
    func drop(_ request: some SessionIntent) throws -> SessionMutation? {
        let windowID: UUID
        let spaceID: UUID
        let selection: TabSelection
        switch request {
        case let value as DropIntoList:
            (windowID, spaceID, selection) = (value.windowID, value.spaceID, value.selection)
        case let value as DropIntoSplit:
            (windowID, spaceID, selection) = (value.windowID, value.spaceID, value.selection)
        case let value as DropOnSpace: (windowID, spaceID, selection) = (value.windowID, value.spaceID, value.selection)
        case let value as DropAroundTab:
            (windowID, spaceID, selection) = (value.windowID, value.spaceID, value.selection)
        default: return nil
        }
        let (_, values, selected) = try selecting(spaceID, windowID: windowID, selection: selection)
        let alone =
            selected.roots.count == 1 && !selected.roots[0].isFolder ? try values.tab(selected.roots[0].id) : nil
        let pinsOnly = !selected.holdsFolders && selected.members.allSatisfy { $0.placement == .pinned }
        if alone == nil && selected.members.contains(where: { $0.placement == .pinned }) && !pinsOnly {
            throw Rejection.pinnedTabsDragAlone(PinnedTabsDragAlone())
        }
        switch request {
        case let value as DropIntoList:
            if let alone, !value.section.holdsFolders {
                return try apply(
                    MoveTab(
                        workspaceID: workspaceID, spaceID: spaceID, tabID: alone.id, placement: value.section,
                        folderID: value.folderID, beforeTabID: value.beforeTabID, leavesSplit: true))
            }
            guard alone != nil || value.section.holdsFolders || pinsOnly else {
                throw Rejection.pinsOneTabAtATime(PinsOneTabAtATime())
            }
            return try apply(
                FileTabs(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    placement: value.section, folderID: value.folderID, beforeTabID: value.beforeTabID,
                    beforeFolderID: value.beforeFolderID, leavesSplits: alone != nil))
        case let value as DropIntoSplit:
            if let alone {
                return try apply(
                    JoinSplit(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, tabID: alone.id,
                        targetTabID: value.targetTabID, index: value.index, appearances: value.appearances))
            }
            guard !pinsOnly else { throw Rejection.pinnedTabsStayPut(PinnedTabsStayPut()) }
            return try apply(
                SplitTabs(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    targetTabID: value.targetTabID, index: value.index, appearances: value.appearances))
        case let value as DropOnSpace:
            if let alone {
                return try apply(
                    MoveTabToSpace(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, tabID: alone.id,
                        destinationSpaceID: value.destinationSpaceID, placement: nil, folderID: nil, beforeTabID: nil,
                        follows: value.follows))
            }
            guard !pinsOnly else { throw Rejection.pinnedTabsStayPut(PinnedTabsStayPut()) }
            return try apply(
                MoveTabsToSpace(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    destinationSpaceID: value.destinationSpaceID, follows: value.follows))
        case let value as DropAroundTab:
            guard let alone else {
                return try apply(
                    FolderTabsAround(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        tabID: value.tabID, title: value.title))
            }
            let target = try values.tab(value.tabID)
            guard target.id != alone.id, !target.placement.isDurable, target.folderID == nil,
                target.splitGroupID == nil, !SessionTabs.isStartPage(target)
            else { throw Rejection.invalidFolderPlacement(InvalidFolderPlacement()) }
            return try apply(
                CreateFolder(
                    workspaceID: workspaceID, spaceID: spaceID, folderID: ids(), placement: .current, parentID: nil,
                    title: nil, color: FolderState.defaultColor, tabIDs: [target.id, alone.id], leavesSplits: true))
        default: preconditionFailure("Unrecognized sidebar drop")
        }
    }
    func moveWithinWorkspace(_ request: MoveTabToWindow) throws -> SessionMutation {
        guard let target = windows[request.destinationWindowID], target.workspaceID == workspaceID else {
            throw Rejection.windowNotOpen(WindowNotOpen(windowID: request.destinationWindowID))
        }
        var original = try space(request.spaceID)
        guard let index = original.tabs.firstIndex(where: { $0.id == request.tabID }) else {
            throw Rejection.unknownTab(UnknownTab(tabID: request.tabID))
        }
        var followUp = window(target.id)
        followUp.showTab(request.tabID, in: original.id)
        followUp.showSpace(original.id)
        if request.windowID != target.id { followUp.depart(request.tabID, in: original.id, from: request.windowID) }
        original.tabs[index].lastActivatedAt = now
        return replacing([original], stage: .tabUse, followUp: followUp)
    }
}
