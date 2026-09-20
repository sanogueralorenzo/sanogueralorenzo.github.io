import Foundation

public struct RuntimeDiscovery: Decodable, Sendable {
    public let protocolVersion: Int
    public let port: Int
    public let token: String
}

public struct RuntimeEnvelope: Decodable, Sendable {
    public let event: RuntimeEvent
}

public struct RuntimeEvent: Decodable, Sendable {
    public let type: String
    public let delta: String?
    public let message: String?
    public let name: String?
    public let session: RuntimeSession?
    public let artifact: RuntimeArtifact?
}

public struct RuntimeArtifact: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let path: String
}

public struct RuntimeSession: Decodable, Sendable {
    public let id: String
}

public struct SetupStatus: Decodable, Sendable {
    public let configured: Bool
    public let openAIConfigured: Bool
    public let codex: CodexSetupStatus
}

public struct CodexSetupStatus: Decodable, Sendable {
    public let installed: Bool
    public let connected: Bool
    public let allowanceAvailable: Bool?
}

public struct SessionList: Decodable, Sendable {
    public let sessions: [RuntimeSession]
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
    public let sessionId: String?
    public let channel = "macos"
    public let requestId: String
    public let fresh: Bool

    public init(text: String, sessionId: String?, requestId: String, fresh: Bool) {
        self.text = text
        self.sessionId = sessionId
        self.requestId = requestId
        self.fresh = fresh
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
