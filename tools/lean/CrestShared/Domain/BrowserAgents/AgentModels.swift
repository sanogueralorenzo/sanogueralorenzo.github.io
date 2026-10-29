import Foundation

/// OS-verified identity. Program fields compare exactly, including Unicode spelling.
struct AgentIdentity: Hashable, Sendable {
    static let maximumField = 255
    static let maximumPath = 1024
    let teamID: String?
    let signingID: String?
    let path: String?
    let client: String?

    var normalized: Self {
        Self(teamID: teamID, signingID: signingID, path: path, client: AgentPreferences.cleanName(client))
    }
    var isValid: Bool {
        func present(_ text: String?) -> Bool { text?.unicodeScalars.contains { !$0.properties.isWhitespace } == true }
        let signed =
            present(teamID) && present(signingID) && path == nil
            && teamID!.utf16.count <= Self.maximumField && signingID!.utf16.count <= Self.maximumField
        let located =
            teamID == nil && signingID == nil
            && path.map {
                (2...Self.maximumPath).contains($0.utf16.count) && $0.hasPrefix("/")
            } == true
        return (signed || located)
            && client.map { (1...AgentPreferences.maximumName).contains($0.utf16.count) } != false
    }
    private var key: [Data?] { [teamID, signingID, path, client].map { $0.map { Data($0.utf8) } } }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

struct ApprovedAgent: Equatable, Sendable {
    let identity: AgentIdentity
    let name: String
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && Data(lhs.name.utf8) == Data(rhs.name.utf8)
    }
}

struct AgentPreferences: Equatable, Sendable {
    static let maximumAgents = 32
    static let maximumName = 64
    static let off = Self(isOn: false, runsScripts: false, spaceIDs: [], agents: [])
    var isOn: Bool
    var runsScripts: Bool
    var spaceIDs: [UUID]
    var agents: [ApprovedAgent]

    func approves(_ identity: AgentIdentity) -> Bool { agents.contains { $0.identity == identity.normalized } }
    mutating func allow(_ space: UUID, _ allowed: Bool) {
        if !allowed { spaceIDs.removeAll { $0 == space } } else if !spaceIDs.contains(space) { spaceIDs.append(space) }
    }
    mutating func approve(_ agent: ApprovedAgent) throws(AgentFailure) {
        let identity = agent.identity.normalized
        guard identity.isValid, let name = Self.cleanName(agent.name) else { throw .invalidAgent }
        let revised = ApprovedAgent(identity: identity, name: name)
        if agents.contains(where: { $0.identity == identity }) {
            agents = agents.map { $0.identity == identity ? revised : $0 }
        } else {
            guard agents.count < Self.maximumAgents else { throw .full }
            agents.append(revised)
        }
    }
    mutating func forget(_ identity: AgentIdentity) { agents.removeAll { $0.identity == identity.normalized } }

    /// Rune-based cleaning preserves Crest's UTF-16 length limit and Unicode boundaries.
    static func cleanName(_ text: String?) -> String? {
        guard let text else { return nil }
        var result = ""
        var length = 0
        var spaced = false
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                spaced = !result.isEmpty
                continue
            default: break
            }
            if scalar.properties.isWhitespace {
                spaced = !result.isEmpty
                continue
            }
            let addition = (spaced ? 1 : 0) + scalar.utf16.count
            if length + addition > maximumName { break }
            if spaced { result.append(" ") }
            spaced = false
            result.unicodeScalars.append(scalar)
            length += addition
        }
        return result.isEmpty ? nil : result
    }
}

struct AgentSessionState: Equatable, Sendable {
    let sessionID: UUID
    let identity: AgentIdentity
    var name: String
    var color: BrandColor?
    var tabIDs: [UUID]
    var opensWindows: Bool
    var activity: [AgentActivity]
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.identity == rhs.identity && Data(lhs.name.utf8) == Data(rhs.name.utf8)
            && lhs.color == rhs.color && lhs.tabIDs == rhs.tabIDs && lhs.opensWindows == rhs.opensWindows
            && lhs.activity == rhs.activity
    }
}
struct AgentActivity: Equatable, Sendable {
    let kind: AgentActivityKind
    let subject: String
    let at: Date
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.at == rhs.at && Data(lhs.subject.utf8) == Data(rhs.subject.utf8)
    }
}
struct AgentReachList: Equatable, Sendable {
    let workspaceID: UUID?
    let spaces: [AgentSpace]
}
struct AgentSpace: Equatable, Sendable {
    let spaceID: UUID
    let name: String
    let tabs: [AgentTab]
}
struct AgentTab: Equatable, Sendable {
    let tabID: UUID
    let title: String
    let url: String?
    let placement: TabPlacement
    let claimed: Bool
}

enum AgentActivityKind: String, CaseIterable, Sendable {
    case openedTab, loadedPage, closedTab, openedWindow, openedPrivateWindow, deletedHistory, ranScript
    var name: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .openedTab: "Opened a tab"
        case .loadedPage: "Loaded a page"
        case .closedTab: "Closed a tab"
        case .openedWindow: "Opened a window"
        case .openedPrivateWindow: "Opened a private window"
        case .deletedHistory: "Deleted history"
        case .ranScript: "Ran a script"
        }
    }
    var symbol: String {
        switch self {
        case .openedTab: "plus.square"
        case .loadedPage: "arrow.right.circle"
        case .closedTab: "xmark.square"
        case .openedWindow: "macwindow.badge.plus"
        case .openedPrivateWindow: "eyeglasses"
        case .deletedHistory: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .ranScript: "curlybraces"
        }
    }
}

enum AgentFailure: Error, Equatable, LocalizedError {
    case unavailable, agentsOff, notApproved, invalidAgent, full, sessionsFull
    case unknownSession(UUID)
    case spaceUnavailable(UUID)
    case tabUnavailable(UUID)
    case tabStopped(UUID)
    case storage(StorageFailure)
    var errorDescription: String? { explanation }
    var explanation: String {
        switch self {
        case .unavailable: String(localized: "Agents can’t use Crest on this device.")
        case .agentsOff: String(localized: "Agents are turned off in Crest’s settings.")
        case .notApproved: String(localized: "The person hasn’t allowed this agent to use Crest.")
        case .unknownSession: String(localized: "This agent is no longer connected to Crest.")
        case .spaceUnavailable: String(localized: "That Space isn’t one agents may use.")
        case .tabUnavailable: String(localized: "That tab isn’t one agents may use.")
        case .tabStopped: String(localized: "The person stopped agents from using this tab.")
        case .invalidAgent: String(localized: "Crest couldn’t tell which program this agent is.")
        case .full: String(localized: "Too many agents are allowed. Forget one in Settings first.")
        case .sessionsFull: String(localized: "Too many agents are using Crest right now.")
        case .storage: String(localized: "Crest couldn’t save this change. Try again.")
        }
    }
}
