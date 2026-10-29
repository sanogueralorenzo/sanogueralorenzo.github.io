import Foundation

/// Native authority for approvals and connections. CoreState is its observed projection.
@MainActor
final class NativeAgents {
    private unowned let core: CrestCore
    private let storage: AgentSQLite?
    private let now: () -> Date
    private var connections = AgentConnections()
    private var workspaceOrder: [UUID] = []
    init(core: CrestCore, now: @escaping () -> Date = Date.init) throws {
        self.core = core
        self.now = now
        storage = try core.storageDirectory.map(AgentSQLite.init(directory:))
        if let storage { core.state.updateAgents(preferences: try storage.read(), sessions: []) }
    }
    func send(_ request: some NativeAgentIntent) throws(AgentFailure) {
        core.drain()
        guard core.platform == .desktop else { throw .unavailable }
        switch request {
        case let request as SetAgents: try revise { $0.isOn = request.isOn }
        case let request as SetAgentScripts: try revise { $0.runsScripts = request.runsScripts }
        case let request as AllowAgentSpace:
            guard !request.allowed || persistent?.spaces.model(request.spaceID) != nil && !isDeleting(request.spaceID)
            else {
                throw .spaceUnavailable(request.spaceID)
            }
            try revise { $0.allow(request.spaceID, request.allowed) }
        case let request as ApproveAgent:
            try revise { (preferences: inout AgentPreferences) throws(AgentFailure) in
                try preferences.approve(request.agent)
            }
        case let request as ForgetAgent: try revise { $0.forget(request.identity) }
        case let request as BeginAgentSession:
            let preferences = core.state.agentPreferences
            guard preferences.isOn else { throw .agentsOff }
            guard preferences.approves(request.identity) else { throw .notApproved }
            let identity = request.identity.normalized
            let name =
                AgentPreferences.cleanName(request.name) ?? preferences.agents.first { $0.identity == identity }!.name
            try connections.begin(request.sessionID, identity, name)
        case let request as EndAgentSession: connections.end { $0.sessionID == request.sessionID }
        case let request as IdentifyAgent:
            var color = request.color.map {
                BrandColor(
                    red: min(max($0.red, 0), 1), green: min(max($0.green, 0), 1), blue: min(max($0.blue, 0), 1),
                    alpha: 1)
            }
            if let value = color, ![value.red, value.green, value.blue].allSatisfy(\.isFinite) { color = nil }
            try connections.identify(request.sessionID, AgentPreferences.cleanName(request.name), color)
        case let request as ClaimAgentTab:
            guard core.state.agentPreferences.isOn, persistent != nil else { throw .agentsOff }
            guard reached.contains(where: { $0.tabs.models.contains { $0.id == request.tabID && offered($0) } }) else {
                throw .tabUnavailable(request.tabID)
            }
            try connections.claim(request.sessionID, request.tabID)
        case let request as StopAgentTab: connections.stop(request.tabID)
        case is StopAllAgents: connections.stopAll()
        case let request as AllowAgentWindows: try connections.allowWindows(request.sessionID)
        case let request as NoteAgentActivity:
            try connections.note(
                request.sessionID, AgentActivity(kind: request.kind, subject: request.subject, at: now()))
        default: preconditionFailure("Unknown native agent action")
        }
        core.state.updateAgents(preferences: core.state.agentPreferences, sessions: connections.all)
        core.state.finishBatch()
    }
    private func revise(_ edit: (inout AgentPreferences) throws(AgentFailure) -> Void) throws(AgentFailure) {
        let before = core.state.agentPreferences
        var next = before
        try edit(&next)
        guard next != before else { return }
        do { try storage?.save(next) } catch let failure as SQLiteConnection.Failure {
            core.storageFailureHandler?(failure.reason)
            throw .storage(failure.reason)
        } catch { throw .storage(.unavailable) }
        connections.end { !next.isOn || !next.approves($0.identity) }
        connections.unstop { !next.isOn || !next.approves($0) }
        prune(using: next)
        core.state.updateAgents(preferences: next, sessions: connections.all)
    }
    /// Session edits have already committed; pruning runs before UI observers.
    func reconcile(_ changes: [any CoreChange] = []) {
        for change in changes {
            if let wire = change as? Change {
                switch wire {
                case .workspaceOpened(let opened):
                    if !workspaceOrder.contains(opened.workspaceID) { workspaceOrder.append(opened.workspaceID) }
                case .workspaceClosed(let closed): workspaceOrder.removeAll { $0 == closed.workspaceID }
                default: break
                }
            }
        }
        prune(using: core.state.agentPreferences)
        core.state.updateAgents(preferences: core.state.agentPreferences, sessions: connections.all)
    }
    /// Matches the existing post-commit device cleanup, reporting a failed disk write.
    func forgetDeletedSpace(_ space: UUID) {
        var next = core.state.agentPreferences
        next.allow(space, false)
        guard next != core.state.agentPreferences else { return }
        do { try storage?.save(next) } catch let failure as SQLiteConnection.Failure {
            core.storageFailureHandler?(failure.reason)
        } catch { core.storageFailureHandler?(.unavailable) }
        prune(using: next)
        core.state.updateAgents(preferences: next, sessions: connections.all)
    }
    func reach(_ sessionID: UUID) -> AgentReachList {
        guard let session = connections.find(sessionID), core.state.agentPreferences.isOn, let persistent else {
            return AgentReachList(workspaceID: nil, spaces: [])
        }
        let stopped = connections.stopped(session.identity)
        return AgentReachList(
            workspaceID: persistent.id,
            spaces: reached.map { space in
                AgentSpace(
                    spaceID: space.id, name: space.settings.name,
                    tabs: space.tabs.models.filter {
                        offered($0) && !stopped.contains($0.id)
                    }.map {
                        AgentTab(
                            tabID: $0.id, title: $0.displayTitle, url: $0.url, placement: $0.placement,
                            claimed: session.tabIDs.contains($0.id))
                    })
            })
    }
    private var persistent: WorkspaceModel? {
        let ordered = workspaceOrder.compactMap { core.state.workspaces[$0] }
        return ordered.first { $0.keepsFile } ?? ordered.first { $0.kind.keepsAppPreferences }
    }
    private func isDeleting(_ space: UUID) -> Bool {
        persistent?.spaceDeletions.contains { $0.spaceID == space } == true
    }
    private var reached: [SpaceModel] { reached(using: core.state.agentPreferences) }
    private func reached(using preferences: AgentPreferences) -> [SpaceModel] {
        guard preferences.isOn, let persistent else { return [] }
        return persistent.spaces.models.filter { preferences.spaceIDs.contains($0.id) && !isDeleting($0.id) }
    }
    private func prune(using preferences: AgentPreferences) {
        let usable = Set(reached(using: preferences).flatMap { $0.tabs.models.filter(offered).map(\.id) })
        connections.prune { usable.contains($0) }
    }
    private func offered(_ tab: TabStateModel) -> Bool {
        guard tab.nativeContent == nil else { return false }
        guard let address = tab.url else { return true }
        if address == "about:blank" { return true }
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false,
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return false }
        return true
    }
}

extension CrestCore {
    func send(_ request: some NativeAgentIntent) throws(AgentFailure) { try agents.send(request) }
    func query(_ request: AgentReach) -> AgentReachList {
        drain()
        return agents.reach(request.sessionID)
    }
}
