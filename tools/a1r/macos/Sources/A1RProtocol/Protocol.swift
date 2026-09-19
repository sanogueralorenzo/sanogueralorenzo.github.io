import Foundation

public struct RuntimeDiscovery: Decodable, Sendable {
    public let protocolVersion: Int
    public let port: Int
    public let token: String
    public let pid: Int
}

public struct RuntimeEnvelope: Decodable, Sendable {
    public let v: Int
    public let seq: Int
    public let requestId: String
    public let event: RuntimeEvent
}

public struct RuntimeEvent: Decodable, Sendable {
    public let type: String
    public let delta: String?
    public let message: String?
    public let name: String?
    public let session: RuntimeSession?
}

public struct RuntimeSession: Decodable, Sendable {
    public let id: String
    public let title: String
    public let kind: String
}

public struct SetupStatus: Decodable, Sendable {
    public let openAIConfigured: Bool
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

public struct APIKeyRequest: Encodable, Sendable {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
