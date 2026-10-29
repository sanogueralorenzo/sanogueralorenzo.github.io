import Foundation

/// The two detached edits of a move. The owner saves them together before accepting either one.
struct SessionTransfer {
    struct Scope {
        let edits: SessionMutations
        let borrowedFrom: UUID?
        let isPrivate: Bool
    }
    let leaving: SessionMutation
    let arriving: SessionMutation

    static func between(_ request: MoveTabToWindow, from source: Scope, to destination: Scope) throws -> Self {
        let leaving = source.edits
        let arriving = destination.edits
        guard let window = arriving.windows[request.destinationWindowID], window.workspaceID == arriving.workspaceID
        else {
            throw Rejection.windowNotOpen(WindowNotOpen(windowID: request.destinationWindowID))
        }
        guard source.isPrivate == destination.isPrivate else {
            throw Rejection.privateWorkspaceBoundary(
                PrivateWorkspaceBoundary(destinationWorkspaceID: arriving.workspaceID))
        }
        guard source.borrowedFrom != nil || destination.borrowedFrom != nil,
            source.borrowedFrom ?? leaving.workspaceID == destination.borrowedFrom ?? arriving.workspaceID
        else {
            throw Rejection.unrelatedWorkspaces(UnrelatedWorkspaces(destinationWorkspaceID: arriving.workspaceID))
        }
        let original = try leaving.space(request.spaceID)
        let there = try arriving.space(request.spaceID)
        guard original.tabs.contains(where: { $0.id == request.tabID }) else {
            throw Rejection.unknownTab(UnknownTab(tabID: request.tabID))
        }
        guard
            !arriving.basis.spaces.contains(where: {
                $0.tabs.contains { $0.id == request.tabID } || $0.archivedTabs.contains { $0.tab.id == request.tabID }
            })
        else { throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: request.tabID)) }
        var values = try SessionTabs(original)
        var receiving = try SessionTabs(there)
        var followLeft = leaving.window(request.windowID)
        var followThere = arriving.window(request.destinationWindowID)
        let fallback = followLeft.fallback(
            in: original.id, dismissing: request.tabID,
            available: Set(original.tabs.filter { $0.id != request.tabID }.map(\.id)))
        let shown = try values.transfer(
            request.tabID, to: &receiving, selected: followLeft.window?.tab(in: original.id), fallback: fallback,
            placement: .current, folder: nil, before: nil, afterSelection: true,
            destinationSelection: followThere.window?.tab(in: there.id), at: leaving.now)
        try receiving.edit(request.tabID) { $0.lastActivatedAt = leaving.now }
        followLeft.showTab(shown, in: original.id)
        followThere.showTab(request.tabID, in: there.id)
        followThere.showSpace(there.id)
        let left = leaving.replacing([values.capture(original)], stage: .transfer, followUp: followLeft)
        let right = arriving.replacing([receiving.capture(there)], stage: .transfer, followUp: followThere)
        try SessionValidation.require(left.session)
        try SessionValidation.require(right.session)
        return Self(leaving: left, arriving: right)
    }
}
