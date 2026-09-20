import Foundation
import AgentProtocol

public enum RuntimeClientError: LocalizedError {
    case notRunning
    case incompatible
    case disconnected
    case invalidEvent
    case badResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Agent runtime is not running."
        case .incompatible: "This Agent runtime uses an incompatible protocol."
        case .disconnected: "Agent runtime disconnected."
        case .invalidEvent: "Agent runtime sent an invalid event."
        case let .badResponse(code, message): "Runtime error \(code): \(message)"
        }
    }
}

public actor RuntimeClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

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
        guard discovery.protocolVersion == 3,
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

    public func runState() async throws -> RunState { try await value(path: "/v1/runs") }

    public func submit(text: String, sessionId: String?, fresh: Bool) async throws -> RunInfo? {
        let body = try JSONEncoder().encode(ChatRequest(text: text, sessionId: sessionId, fresh: fresh))
        let (data, response) = try await session.data(for: request(path: "/v1/runs", method: "POST", body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409 { return nil }
        guard (200..<300).contains(status) else {
            throw RuntimeClientError.badResponse(status, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(RunStartResponse.self, from: data).run
    }

    public func events(after: Int) throws -> AsyncThrowingStream<RunEnvelope, Error> {
        let request = try request(path: "/v1/events?after=\(after)")
        let (stream, continuation) = AsyncThrowingStream<RunEnvelope, Error>.makeStream()
        let task = Task { [session] in
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw RuntimeClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0, "Could not observe Agent")
                }
                for try await line in bytes.lines where line.hasPrefix("data: ") {
                    guard let data = line.dropFirst(6).data(using: .utf8) else { continue }
                    continuation.yield(try JSONDecoder().decode(RunEnvelope.self, from: data))
                }
                if Task.isCancelled { continuation.finish() }
                else { continuation.finish(throwing: RuntimeClientError.disconnected) }
            } catch is DecodingError {
                continuation.finish(throwing: RuntimeClientError.invalidEvent)
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stop() async throws -> Bool {
        let result: StopResponse = try await value(path: "/v1/runs/stop", method: "POST")
        return result.stopped
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RuntimeClientError.badResponse(0, "Invalid runtime URL")
        }
        var request = URLRequest(url: url)
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
}

private struct RunStartResponse: Decodable { let run: RunInfo }
private struct StopResponse: Decodable { let stopped: Bool }
