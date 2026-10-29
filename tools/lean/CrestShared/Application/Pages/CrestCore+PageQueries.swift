import Foundation

extension CrestCore {
    func query(_ question: PageHistoryEntries) -> PageHistoryList {
        drain()
        let history = pages.page(question.pageID)?.history
        return PageHistoryList(back: history?.back ?? [], forward: history?.forward ?? [])
    }
    func query(_ question: ArchivedPageHistory) -> PageHistoryArchive {
        drain()
        return PageHistoryArchive(archive: pages.archivedHistory(question.pageID))
    }
    func query(_ question: IdlePages) -> IdlePageList {
        drain()
        return IdlePageList(pages: pages.idlePages())
    }
    func query(_ question: CanReturnToSavedAddress) throws -> SavedAddressReturn {
        drain()
        guard let workspace = state.workspaces[question.workspaceID] else {
            throw NativePages.Failure.unknownWorkspace(question.workspaceID)
        }
        guard let tab = workspace.spaces.model(question.spaceID)?.tabs.model(question.tabID),
            tab.placement.isDurable, let saved = tab.savedURL ?? tab.url
        else {
            return SavedAddressReturn(changesPage: false)
        }
        let address = pages.showing(workspace: workspace.id, window: question.windowID, tab: tab.id)?.address ?? tab.url
        return SavedAddressReturn(changesPage: address.map { !PageAddress.samePage($0, saved) } ?? false)
    }
    func query(_ question: LinkNavigation) -> LinkNavigationAnswer {
        drain()
        let page = pages.page(question.pageID)
        let tab = page.flatMap {
            state.workspaces[$0.workspaceID]?.spaces.model($0.spaceID)?.tabs.model($0.tabID ?? UUID())
        }
        return LinkNavigationAnswer(
            decision: PageLinkDecision.resolve(
                question.url, gesture: question.gesture,
                hasContext: tab != nil, placement: tab?.placement,
                saved: tab.flatMap { $0.placement.isDurable ? $0.savedURL ?? $0.url : nil }))
    }
}

enum PageLinkDecision {
    static func selectsWindow(_ gesture: LinkGesture) -> Bool {
        !(gesture.modifiers.contains(.command) || gesture.middleClick) || gesture.modifiers.contains(.shift)
    }

    static func resolve(
        _ destination: String?, gesture: LinkGesture, hasContext: Bool, placement: TabPlacement?, saved: String?
    ) -> LinkNavigationDecision {
        guard gesture.userActivated, let target = host(destination) else { return .navigate }
        if gesture.topLevel && hasContext && gesture.modifiers.contains(.option) { return .foregroundTab }
        if gesture.modifiers.contains(.command) || gesture.middleClick {
            return gesture.modifiers.contains(.shift) ? .foregroundTab : .backgroundTab
        }
        if gesture.topLevel && hasContext && placement?.isDurable == true, let saved = host(saved), saved != target {
            return .foregroundTab
        }
        return .navigate
    }
    private static func host(_ spelling: String?) -> String? {
        guard let spelling, let url = URL(string: spelling.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host?.lowercased(), !host.isEmpty,
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
