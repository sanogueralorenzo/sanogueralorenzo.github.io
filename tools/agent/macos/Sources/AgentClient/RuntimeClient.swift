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

public final class EventStream: AsyncSequence, Sendable {
    public typealias Element = RunEnvelope

    private let bytes: URLSession.AsyncBytes

    init(bytes: URLSession.AsyncBytes) { self.bytes = bytes }

    deinit { bytes.task.cancel() }

    public func makeAsyncIterator() -> Iterator {
        Iterator(stream: self)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let stream: EventStream
        private var lines: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator
        private var first = true

        init(stream: EventStream) {
            self.stream = stream
            lines = stream.bytes.lines.makeAsyncIterator()
        }

        public mutating func next() async throws -> RunEnvelope? {
            do {
                while let line = try await lines.next() {
                    guard line.hasPrefix("data: ") else { continue }
                    guard let data = line.dropFirst(6).data(using: .utf8) else { continue }
                    let envelope = try JSONDecoder().decode(RunEnvelope.self, from: data)
                    if envelope.event.type == "snapshot" && envelope.event.snapshot == nil {
                        throw RuntimeClientError.invalidEvent
                    }
                    if first && envelope.event.type != "snapshot" && envelope.event.type != "navigate" {
                        throw RuntimeClientError.incompatible
                    }
                    first = false
                    return envelope
                }
                if Task.isCancelled { return nil }
                throw RuntimeClientError.disconnected
            } catch is DecodingError {
                throw RuntimeClientError.invalidEvent
            }
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
        guard discovery.protocolVersion == 1,
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

    public func logout() async throws {
        _ = try await data(path: "/v1/setup/logout", method: "POST")
    }

    public func connectOpenAI(key: String) async throws {
        _ = try await data(path: "/v1/setup/openai", method: "POST", body: ["apiKey": key])
    }

    public func startCodexLogin(mode: String) async throws -> CodexLoginStart {
        try await value(path: "/v1/setup/codex/login", method: "POST", body: ["mode": mode])
    }

    public func waitForCodexLogin(loginId: String) async throws -> CodexLoginResult {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        return try await value(path: "/v1/setup/codex/login/\(id)/wait", method: "POST")
    }

    public func sessions() async throws -> [RuntimeSession] {
        let response: SessionsResponse = try await value(path: "/v1/sessions")
        return response.sessions
    }

    public func openSession(fresh: Bool = false, preferredSessionId: String? = nil) async throws -> RuntimeSession {
        let response: OpenSessionResponse = try await value(
            path: fresh ? "/v1/sessions" : "/v1/sessions/auto", method: "POST",
            body: preferredSessionId.map { ["preferredSessionId": $0] })
        return response.session
    }

    public func submit(text: String, sessionId: String, requestId: String? = nil) async throws -> RunInfo? {
        let body = try JSONEncoder().encode(ChatRequest(text: text, sessionId: sessionId, requestId: requestId))
        let (data, response) = try await session.data(for: request(path: "/v1/runs", method: "POST", body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409 { return nil }
        guard (200..<300).contains(status) else {
            throw RuntimeClientError.badResponse(status, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(RunStartResponse.self, from: data).run
    }

    public func events(sessionId: String, runId: String? = nil) async throws -> EventStream {
        let id = sessionId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionId
        let pending = runId.map { "&runId=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
        let request = try request(path: "/v1/events?sessionId=\(id)\(pending)")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RuntimeClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0, "Could not observe Agent")
        }
        guard http.value(forHTTPHeaderField: "X-Agent-Stream") == "snapshot" else {
            throw RuntimeClientError.incompatible
        }
        return EventStream(bytes: bytes)
    }

    public func stop(runId: String) async throws -> Bool {
        let result: StopResponse = try await value(path: "/v1/runs/stop", method: "POST", body: ["runId": runId])
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
private struct SessionsResponse: Decodable { let sessions: [RuntimeSession] }
private struct OpenSessionResponse: Decodable { let session: RuntimeSession }
