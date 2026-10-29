import Foundation

protocol NativeAgentIntent: Sendable {}

struct AllowAgentSpace: NativeAgentIntent, Equatable, Sendable {
    let spaceID: UUID
    let allowed: Bool
}

struct AllowAgentWindows: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
}

struct ApproveAgent: NativeAgentIntent, Equatable, Sendable {
    let agent: ApprovedAgent
}

struct BeginAgentSession: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
    let identity: AgentIdentity
    let name: String
}

struct ClaimAgentTab: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
    let tabID: UUID
}

struct EndAgentSession: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
}

struct ForgetAgent: NativeAgentIntent, Equatable, Sendable {
    let identity: AgentIdentity
}

struct IdentifyAgent: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
    let name: String?
    let color: BrandColor?
}

struct NoteAgentActivity: NativeAgentIntent, Equatable, Sendable {
    let sessionID: UUID
    let kind: AgentActivityKind
    let subject: String
}

struct SetAgentScripts: NativeAgentIntent, Equatable, Sendable {
    let runsScripts: Bool
}

struct SetAgents: NativeAgentIntent, Equatable, Sendable {
    let isOn: Bool
}

struct StopAgentTab: NativeAgentIntent, Equatable, Sendable {
    let tabID: UUID
}

struct StopAllAgents: NativeAgentIntent, Equatable, Sendable {
}

struct AgentReach: Equatable, Sendable {
    let sessionID: UUID
}
