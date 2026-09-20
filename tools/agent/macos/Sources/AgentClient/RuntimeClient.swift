import Foundation
import AgentProtocol

public enum RuntimeClientError: LocalizedError {
    case notRunning
    case incompatible
    case busy
    case disconnected
    case invalidEvent
    case badResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Agent runtime is not running."
        case .incompatible: "This Agent runtime uses an incompatible protocol."
        case .busy: "A response is already running."
        case .disconnected: "Agent runtime disconnected before the response completed."
        case .invalidEvent: "Agent runtime sent an invalid event."
        case let .badResponse(code, message): "Runtime error \(code): \(message)"
        }
    }
}

public actor RuntimeClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private var activeRequest: Task<Void, Never>?

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public static func discover() throws -> RuntimeClient {
        let homeDirectory: URL
        if let configured = ProcessInfo.processInfo.environment["AGENT_HOME"], !configured.isEmpty {
            let expanded = configured.hasPrefix("~/")
                ? FileManager.default.homeDirectoryForCurrentUser.appending(path: String(configured.dropFirst(2)))
                : URL(filePath: configured)
            homeDirectory = expanded.standardizedFileURL
        } else {
            homeDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agent")
        }
        guard let data = try? Data(contentsOf: homeDirectory.appending(path: "runtime.json")) else {
            throw RuntimeClientError.notRunning
        }
        let discovery = try JSONDecoder().decode(RuntimeDiscovery.self, from: data)
        guard discovery.protocolVersion == 2,
              let baseURL = URL(string: "http://127.0.0.1:\(discovery.port)") else {
            throw RuntimeClientError.incompatible
        }
        return RuntimeClient(baseURL: baseURL, token: discovery.token)
    }

    public func health() async -> Bool {
        do {
            let (_, response) = try await session.data(for: request(path: "/v1/health"))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func setupStatus() async throws -> SetupStatus { try await value(path: "/v1/setup") }

    public func connectOpenAI(key: String) async throws {
        _ = try await data(path: "/v1/setup/openai", method: "POST", body: ["apiKey": key])
    }

    public func selectBackend(_ backend: String) async throws {
        _ = try await data(path: "/v1/setup/backend", method: "POST", body: ["backend": backend])
    }

    public func startCodexLogin(mode: String) async throws -> CodexLoginStart {
        try await value(path: "/v1/setup/codex/login", method: "POST", body: ["mode": mode])
    }

    public func waitForCodexLogin(loginId: String) async throws -> CodexLoginResult {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        return try await value(path: "/v1/setup/codex/login/\(id)/wait", method: "POST")
    }

    public func resumeLatest() async throws -> Transcript? {
        let sessions: SessionList = try await value(path: "/v1/sessions")
        guard let session = sessions.sessions.first else { return nil }
        let id = session.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.id
        return try await value(path: "/v1/sessions/\(id)/messages")
    }

    public func events(text: String, sessionId: String?, fresh: Bool) throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        guard activeRequest == nil else { throw RuntimeClientError.busy }
        let body = try JSONEncoder().encode(ChatRequest(text: text, sessionId: sessionId, fresh: fresh))
        let request = try request(path: "/v1/chat", method: "POST", body: body)
        let (stream, continuation) = AsyncThrowingStream<RuntimeEvent, Error>.makeStream()
        let task = Task { [session] in
            do {
                var terminal = false
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw RuntimeClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0, "Could not start response")
                }
                for try await line in bytes.lines where line.hasPrefix("data: ") {
                    guard let data = line.dropFirst(6).data(using: .utf8) else { continue }
                    let event = try JSONDecoder().decode(RuntimeEvent.self, from: data)
                    terminal = terminal || event.isTerminal
                    continuation.yield(event)
                }
                if !terminal { throw RuntimeClientError.disconnected }
                self.finished()
                continuation.finish()
            } catch is DecodingError {
                self.finished()
                continuation.finish(throwing: RuntimeClientError.invalidEvent)
            } catch {
                self.finished()
                continuation.finish(throwing: error)
            }
        }
        activeRequest = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func cancel() -> Bool {
        guard let activeRequest else { return false }
        activeRequest.cancel()
        return true
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 310
        return request
    }

    private func data(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> Data {
        let encoded = try body.map { try JSONEncoder().encode($0) }
        let (data, response) = try await session.data(for: try request(path: path, method: method, body: encoded))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RuntimeClientError.badResponse(status, String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private func value<T: Decodable>(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path: path, method: method, body: body))
    }

    private func finished() {
        activeRequest = nil
    }
}
