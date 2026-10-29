import Foundation

extension SessionMutations {
    func tabEdit(_ request: some SessionIntent) throws -> SessionMutation? {
        switch request {
        case let request as OpenTab:
            let original = try space(request.spaceID)
            guard !basis.spaces.contains(where: { $0.tabs.contains { $0.id == request.tabID } }) else {
                throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: request.tabID))
            }
            var values = try SessionTabs(original)
            let tab = try newTab(request.tabID, content: request.content, placement: request.placement)
            let insertion = try request.afterTabID.flatMap { try values.insertionAfter($0) }
            try values.insert(tab, at: insertion)
            var followUp = window(request.windowID)
            if request.shows {
                followUp.showTab(tab.id, in: original.id)
                followUp.showSpace(original.id)
            }
            return replacing([values.capture(original)], stage: .creation, followUp: followUp)
        case let request as NavigateTab:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            let tab = try values.tab(request.tabID)
            let address = try absolute(request.url)
            let scheme = address.scheme?.lowercased()
            guard
                ["http", "https", "file"].contains(scheme) || request.url == "about:blank"
                    || request.url.hasPrefix("about:blank#")
            else {
                throw Rejection.unsupportedAddress(UnsupportedAddress(url: request.url))
            }
            if tab.nativeContent == nil && tab.url != nil { return SessionMutation(session: basis, stage: .pageReport) }
            let host = URLComponents(url: address, resolvingAgainstBaseURL: false)?.host?.lowercased() ?? ""
            try values.edit(tab.id) {
                $0.url = request.url
                $0.nativeContent = nil
                $0.title = host.isEmpty ? request.url : host
            }
            return replacing([values.capture(original)], stage: .pageReport)
        case let request as OpenAddress:
            let original = try space(request.spaceID)
            var followUp = window(request.windowID)
            let shown = original.tabs.first { $0.id == followUp.window?.tab(in: original.id) }
            if let shown, SessionTabs.isStartPage(shown) {
                var navigated = try tabEdit(
                    NavigateTab(workspaceID: workspaceID, spaceID: original.id, tabID: shown.id, url: request.address))!
                followUp.showTab(shown.id, in: original.id)
                followUp.showSpace(original.id)
                navigated.followUp = followUp
                return navigated
            }
            return try tabEdit(
                OpenTab(
                    workspaceID: workspaceID, windowID: request.windowID, spaceID: original.id, tabID: request.tabID,
                    content: TabContent(address: request.address, view: nil, title: nil), placement: .current,
                    afterTabID: shown?.id, shows: true))
        case let request as ShowStartPage:
            let original = try space(request.spaceID)
            let values = try SessionTabs(original)
            var followUp = window(request.windowID)
            let draft = try original.tabs.first { tab in
                guard SessionTabs.isStartPage(tab), !tab.placement.isDurable else { return false }
                return try !request.outsideSplits || values.splitMembers(tab.id).count < 2
            }
            guard let draft else {
                return try tabEdit(
                    OpenTab(
                        workspaceID: workspaceID, windowID: request.windowID, spaceID: original.id,
                        tabID: request.tabID,
                        content: TabContent(address: nil, view: nil, title: nil), placement: .current,
                        afterTabID: followUp.window?.tab(in: original.id), shows: true))
            }
            var next = original
            next.tabs[next.tabs.firstIndex { $0.id == draft.id }!].lastActivatedAt = now
            followUp.showTab(draft.id, in: original.id)
            followUp.showSpace(original.id)
            return replacing([next], stage: .tabUse, followUp: followUp)
        case let request as CloseTab:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            let tab = try values.tab(request.tabID)
            if !tab.placement.isDurable && SessionTabs.isStartPage(tab) && original.tabs.count < 2 {
                throw Rejection.lastStartPage(LastStartPage(tabID: tab.id))
            }
            var followUp = window(request.windowID)
            let shown = followUp.window?.tab(in: original.id)
            let selected: UUID?
            var effects: [any CoreChange] = []
            if tab.placement.isDurable {
                let available = Set(
                    original.tabs.filter {
                        $0.id != tab.id && (tab.splitGroupID == nil || $0.splitGroupID != tab.splitGroupID)
                    }.map(\.id))
                let fallback = followUp.fallback(in: original.id, dismissing: tab.id, available: available)
                selected = shown == tab.id ? fallback : shown
                effects = [
                    TabPagePutAway(
                        workspaceID: workspaceID, windowID: request.windowID, spaceID: original.id, tabID: tab.id,
                        keepsState: true)
                ]
            } else {
                let fallback = followUp.fallback(
                    in: original.id, dismissing: tab.id, available: Set(original.tabs.map(\.id)))
                selected = try values.dismiss(
                    [tab.id], selected: shown, fallback: fallback, at: now, deleting: false, ensuresSelection: false,
                    resetsPlacement: false)
            }
            followUp.showTab(selected, in: original.id)
            return replacing([values.capture(original)], stage: .creation, followUp: followUp, effects: effects)
        case let request as DeleteTab:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            _ = try values.tab(request.tabID)
            var followUp = window(request.windowID)
            let fallback = followUp.fallback(
                in: original.id, dismissing: request.tabID, available: Set(original.tabs.map(\.id)))
            let selected = try values.dismiss(
                [request.tabID], selected: followUp.window?.tab(in: original.id), fallback: fallback, at: now,
                deleting: true, ensuresSelection: true, resetsPlacement: true)
            followUp.showTab(selected, in: original.id)
            return replacing([values.capture(original)], stage: .deletion, followUp: followUp)
        case let request as ClearCurrentTabs:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            let open = values.tabs.filter { !$0.placement.isDurable }.map(\.id)
            guard !open.isEmpty else { throw Rejection.noCurrentTabs(NoCurrentTabs(spaceID: original.id)) }
            var followUp = window(request.windowID)
            let selected = try values.dismiss(
                open, selected: followUp.window?.tab(in: original.id), fallback: nil, at: now, deleting: false,
                ensuresSelection: true, resetsPlacement: false)
            followUp.showTab(selected, in: original.id)
            return replacing([values.capture(original)], stage: .creation, followUp: followUp)
        case let request as DuplicateTab:
            let original = try space(request.spaceID)
            var values = try SessionTabs(original)
            guard !SessionTabs.isStartPage(try values.tab(request.tabID)) else {
                throw Rejection.startPageNotCopied(StartPageNotCopied(tabID: request.tabID))
            }
            let copy = try values.duplicate(request.tabID, ids: ids, at: now, placement: request.placement ?? .current)
            let effects = try startingCopies(
                [SessionTabs.Copy(source: request.tabID, copy: copy.id)], in: &values, appearances: request.appearances)
            var followUp = window(request.windowID)
            if request.shows {
                followUp.showTab(copy.id, in: original.id)
                followUp.showSpace(original.id)
            }
            return replacing([values.capture(original)], stage: .creation, followUp: followUp, effects: effects)
        case let request as TogglePin:
            let original = try space(request.spaceID)
            let pinned = original.tabs.first { $0.id == request.tabID }?.placement == .pinned
            return try tabEdit(
                MoveTab(
                    workspaceID: workspaceID, spaceID: original.id, tabID: request.tabID,
                    placement: pinned ? .current : .pinned, folderID: nil, beforeTabID: nil, leavesSplit: false))
        case let request as MoveTab:
            return try organizing(request.spaceID) {
                try $0.move(
                    request.tabID, to: request.placement, folder: request.folderID, before: request.beforeTabID,
                    detachSplit: request.leavesSplit || !request.placement.holdsSplits, at: now)
            }
        default: return nil
        }
    }
}
