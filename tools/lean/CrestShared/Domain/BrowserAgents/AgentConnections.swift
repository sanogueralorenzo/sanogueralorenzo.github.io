import Foundation

/// Process-local connections and per-program stopped tabs. Nothing here is persisted.
struct AgentConnections {
    static let maximumSessions = 16
    static let maximumTabs = 64
    static let maximumActivity = 50
    static let maximumActivitySubject = 300
    private(set) var all: [AgentSessionState] = []
    private var stoppedTabs: [AgentIdentity: Set<UUID>] = [:]

    func stopped(_ identity: AgentIdentity) -> Set<UUID> { stoppedTabs[identity] ?? [] }
    func find(_ id: UUID) -> AgentSessionState? { all.first { $0.sessionID == id } }
    @discardableResult
    mutating func begin(_ id: UUID, _ identity: AgentIdentity, _ name: String) throws(AgentFailure) -> Bool {
        guard find(id) == nil else { return false }
        guard all.count < Self.maximumSessions else { throw .sessionsFull }
        all.append(
            AgentSessionState(
                sessionID: id, identity: identity, name: name, color: nil, tabIDs: [], opensWindows: false, activity: []
            ))
        return true
    }
    @discardableResult
    mutating func identify(_ id: UUID, _ name: String?, _ color: BrandColor?) throws(AgentFailure) -> Bool {
        try revise(id) {
            if let name { $0.name = name }
            if let color { $0.color = color }
        }
    }
    @discardableResult
    mutating func claim(_ id: UUID, _ tab: UUID) throws(AgentFailure) -> Bool {
        guard let session = find(id) else { throw .unknownSession(id) }
        guard !stopped(session.identity).contains(tab) else { throw .tabStopped(tab) }
        if session.tabIDs.contains(tab) { return false }
        guard session.tabIDs.count < Self.maximumTabs else { throw .tabUnavailable(tab) }
        return try revise(id) { $0.tabIDs.append(tab) }
    }
    @discardableResult
    mutating func stop(_ tab: UUID) -> Bool {
        var changed = false
        for i in all.indices where all[i].tabIDs.contains(tab) {
            stoppedTabs[all[i].identity, default: []].insert(tab)
            all[i].tabIDs.removeAll { $0 == tab }
            changed = true
        }
        return changed
    }
    @discardableResult
    mutating func stopAll() -> Bool {
        guard !all.isEmpty else { return false }
        for session in all { stoppedTabs[session.identity, default: []].formUnion(session.tabIDs) }
        all.removeAll()
        return true
    }
    @discardableResult
    mutating func allowWindows(_ id: UUID) throws(AgentFailure) -> Bool { try revise(id) { $0.opensWindows = true } }
    @discardableResult
    mutating func note(_ id: UUID, _ activity: AgentActivity) throws(AgentFailure) -> Bool {
        let subject = String(decoding: activity.subject.utf16.prefix(Self.maximumActivitySubject), as: UTF16.self)
        return try revise(id) {
            $0.activity.append(AgentActivity(kind: activity.kind, subject: subject, at: activity.at))
            $0.activity = Array($0.activity.suffix(Self.maximumActivity))
        }
    }
    @discardableResult
    mutating func end(where ends: (AgentSessionState) -> Bool) -> Bool {
        let count = all.count
        all.removeAll(where: ends)
        return all.count != count
    }
    mutating func unstop(where forgets: (AgentIdentity) -> Bool) {
        for identity in stoppedTabs.keys.filter(forgets) { stoppedTabs[identity] = nil }
    }
    @discardableResult
    mutating func prune(_ reachable: (UUID) -> Bool) -> Bool {
        var changed = false
        for i in all.indices {
            let tabs = all[i].tabIDs.filter(reachable)
            if tabs != all[i].tabIDs {
                all[i].tabIDs = tabs
                changed = true
            }
        }
        return changed
    }
    private mutating func revise(_ id: UUID, _ action: (inout AgentSessionState) -> Void) throws(AgentFailure) -> Bool {
        guard let i = all.firstIndex(where: { $0.sessionID == id }) else { throw .unknownSession(id) }
        let before = all[i]
        action(&all[i])
        return before != all[i]
    }
}
