import Foundation

extension SessionMutations {
    func selecting(_ spaceID: UUID, windowID: UUID, selection: TabSelection) throws -> (
        SpaceState.Seed, SessionTabs, SessionSelection
    ) {
        guard window(windowID).window?.shownSpaceID == spaceID else {
            throw Rejection.selectionChanged(SelectionChanged())
        }
        let original = try space(spaceID)
        let values = try SessionTabs(original)
        return (original, values, try values.select(selection))
    }
    func joining(
        _ original: SpaceState.Seed, values: SessionTabs, windowID: UUID, tab: UUID, target: UUID, index: Int?,
        appearances: [TabPageAppearance]?
    ) throws -> SessionMutation {
        var values = values
        let joined = try values.join(tab, to: target, index: index, ids: ids, at: now)
        let effects = try startingCopies(joined.copies, in: &values, appearances: appearances)
        var followUp = window(windowID)
        followUp.showTab(joined.selected, in: original.id)
        followUp.showSpace(original.id)
        return replacing([values.capture(original)], stage: .edit, followUp: followUp, effects: effects)
    }
    func organizationEdit(_ request: some SessionIntent) throws -> SessionMutation? {
        switch request {
        case let request as RenameTab:
            return try organizing(request.spaceID) { try $0.rename(request.tabID, title: request.title, at: now) }
        case let request as ReturnToSavedAddress:
            return try organizing(request.spaceID) { values in
                let tab = try values.tab(request.tabID)
                guard let saved = tab.placement.isDurable ? tab.savedURL ?? tab.url : nil else {
                    throw Rejection.noSavedAddress(NoSavedAddress(tabID: tab.id))
                }
                try values.edit(tab.id) { $0.url = saved }
            }
        case let request as CollapseFolder:
            return try organizing(request.spaceID) {
                try $0.collapseFolder(request.folderID, collapsed: request.collapsed, at: now)
            }
        case let request as CreateFolder:
            return try organizing(request.spaceID, stage: .creation) {
                try $0.addFolder(
                    request.folderID, name: folderTitle(request.title), location: request.placement,
                    parent: request.parentID)
                if let color = request.color { try $0.colorFolder(request.folderID, color: color) }
                if !request.tabIDs.isEmpty {
                    try $0.file(
                        request.tabIDs, at: request.placement, folder: request.folderID, now: now,
                        detachesSplitMembers: request.leavesSplits)
                }
            }
        case let request as DeleteFolder:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            let deleted = try values.deleteFolder(request.folderID, at: now)
            var next = values.capture(original)
            if deleted.contains(where: { $0.source == .gitHubPullRequests }) {
                next.settings.isGitHubFolderDismissed = true
            }
            return replacing([next], stage: .deletion)
        case let request as RenameFolder:
            return try organizing(request.spaceID) { try $0.renameFolder(request.folderID, name: request.title) }
        case let request as SetFolderColor:
            return try organizing(request.spaceID) { try $0.colorFolder(request.folderID, color: request.color) }
        case let request as MoveFolder:
            return try organizing(request.spaceID) {
                try $0.moveFolder(
                    request.folderID, location: request.placement, parent: request.parentID, at: now,
                    beforeFolder: request.beforeFolderID, beforeTab: request.beforeTabID)
            }
        case let request as FileTabs:
            var (original, values, selected) = try selecting(
                request.spaceID, windowID: request.windowID, selection: request.selection)
            try values.file(
                selected, at: request.placement, folder: request.folderID, before: request.beforeTabID,
                beforeFolder: request.beforeFolderID, leavesSplits: request.leavesSplits, now: now)
            return replacing([values.capture(original)], stage: .batch, followUp: window(request.windowID))
        case let request as JoinSplit:
            let original = try space(request.spaceID)
            return try joining(
                original, values: SessionTabs(original), windowID: request.windowID, tab: request.tabID,
                target: request.targetTabID, index: request.index, appearances: request.appearances)
        case let request as OpenLinkInSplit:
            let original = try space(request.spaceID)
            guard !basis.spaces.contains(where: { $0.tabs.contains { $0.id == request.tabID } }) else {
                throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: request.tabID))
            }
            var values = try SessionTabs(original)
            var tab = TabState.Seed.startPage(id: request.tabID, lastActivatedAt: now)
            tab.url = request.address
            tab.title = request.title
            tab.symbol = TabIconMode.webSymbol
            try values.insert(SessionTabs.restored(tab))
            return try joining(
                original, values: values, windowID: request.windowID, tab: tab.id, target: request.targetTabID,
                index: nil, appearances: request.appearances)
        case let request as LeaveSplit:
            return try organizing(request.spaceID) { try $0.leaveSplit(request.tabID, at: now) }
        case let request as DissolveSplit:
            return try organizing(request.spaceID) { $0.dissolveSplit(request.groupID, at: now) }
        case let request as MoveSplitMember:
            return try organizing(request.spaceID) { try $0.moveSplitMember(request.tabID, to: request.index, at: now) }
        case let request as StepSplitMember:
            return try organizing(request.spaceID) {
                guard try $0.stepSplitMember(request.tabID, offset: request.offset, at: now) else {
                    throw Rejection.noSplitStep(NoSplitStep(tabID: request.tabID, offset: request.offset))
                }
            }
        default: return nil
        }
    }
    func folderTitle(_ title: String?) -> String {
        title.flatMap { BrowserAddress.trimmed($0).isEmpty ? nil : $0 } ?? "New Folder"
    }
}
