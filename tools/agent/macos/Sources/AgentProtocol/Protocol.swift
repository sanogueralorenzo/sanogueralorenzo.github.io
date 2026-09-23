import Foundation

public struct RuntimeDiscovery: Decodable, Sendable {
    public let protocolVersion: Int
    public let port: Int
    public let token: String
}

public struct RuntimeEvent: Decodable, Sendable {
    public let type: String
    public let snapshot: RuntimeSnapshot?
    public let text: String?
    public let channel: String?
    public let hasAttachments: Bool?
    public let delta: String?
    public let message: String?
    public let name: String?
    public let sessionId: String?
    public let session: RuntimeSession?
    public let artifact: RuntimeArtifact?
    public let url: String?
    public let continues: Bool?
    public let entry: HomeEntry?
    public let id: String?
    public let tasks: [QueuedTask]?

    public var isTerminal: Bool { type == "done" || type == "error" }
}

public struct RunInfo: Decodable, Sendable {
    public let id: String
    public let sessionId: String
    public let origin: String
}

public struct RunEnvelope: Decodable, Sendable {
    public let sessionId: String
    public let runId: String
    public let event: RuntimeEvent
}

public struct RuntimeSnapshot: Decodable, Sendable {
    public let sessions: [RuntimeSession]
    public let homeEntries: [HomeEntry]
    public let queuedTasks: [QueuedTask]
    public let transcript: Transcript?
    public let activeRuns: [ActiveRunSnapshot]
    public let lastRuns: [LastRunSnapshot]
}

public struct QueuedTask: Decodable, Sendable, Identifiable {
    public let id: String
    public let sessionId: String
    public let text: String
    public let channel: String
    public let createdAt: String
}

public struct HomeEntry: Decodable, Sendable, Identifiable {
    public let id: String
    public let sessionId: String?
    public let title: String?
    public let body: String
    public let requests: [HomeRequest]
    public let summary: String?
    public let state: String?
    public let url: String?
    public let updatedAt: String

    public init(id: String, sessionId: String? = nil, title: String? = nil, body: String, requests: [HomeRequest] = [],
                summary: String? = nil, state: String? = nil, url: String? = nil, updatedAt: String) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.body = body
        self.requests = requests
        self.summary = summary
        self.state = state
        self.url = url
        self.updatedAt = updatedAt
    }
}

public struct HomeRequest: Decodable, Sendable {
    public let text: String
    public let createdAt: String

    public init(text: String, createdAt: String) {
        self.text = text
        self.createdAt = createdAt
    }
}

public struct ActiveRunSnapshot: Decodable, Sendable {
    public let run: RunInfo
    public let turn: TurnSnapshot
    public let session: RuntimeSession?
    public let output: String
    public let artifacts: [RuntimeArtifact]
    public let navigation: NavigationSnapshot?
}

public struct NavigationSnapshot: Decodable, Sendable {
    public let session: RuntimeSession
    public let url: String
    public let continues: Bool?
}

public struct TurnSnapshot: Decodable, Sendable {
    public let text: String
    public let channel: String
    public let hasAttachments: Bool
}

public struct LastRunSnapshot: Decodable, Sendable {
    public let id: String
    public let sessionId: String
    public let state: String
}

public struct RuntimeArtifact: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let path: String
}

public struct RuntimeSession: Decodable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let activeRunId: String?
}

public struct SetupStatus: Decodable, Sendable {
    public let configured: Bool
    public let authMode: String?
    public let codex: CodexSetupStatus
}

public struct CodexSetupStatus: Decodable, Sendable {
    public let installed: Bool
    public let connected: Bool
}

public struct Transcript: Decodable, Sendable {
    public let session: RuntimeSession
    public let messages: [TranscriptMessage]
}

public struct TranscriptMessage: Decodable, Sendable {
    public let role: String
    public let content: String
}

public struct ChatRequest: Encodable, Sendable {
    public let text: String
    public let sessionId: String
    public let requestId: String?
    public let attachmentIds: [String]?
    public let channel = "macos"

    public init(text: String, sessionId: String, requestId: String? = nil, attachmentIds: [String] = []) {
        self.text = text
        self.sessionId = sessionId
        self.requestId = requestId
        self.attachmentIds = attachmentIds.isEmpty ? nil : attachmentIds
    }
}

public struct CodexLoginStart: Decodable, Sendable {
    public let type: String
    public let loginId: String
    public let authUrl: String?
}

public struct CodexLoginResult: Decodable, Sendable {
    public let state: String
    public let error: String?
}
