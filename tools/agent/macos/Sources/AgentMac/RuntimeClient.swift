import Foundation
import AgentProtocol

enum RuntimeClientError: LocalizedError {
    case notRunning
    case incompatible
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "Agent runtime is not running."
        case .incompatible: "This Agent runtime uses an incompatible protocol."
        case let .badResponse(code, message): "Runtime error \(code): \(message)"
        }
    }
}

struct RuntimeClient: Sendable {
    let baseURL: URL
    let token: String

    static func discover() throws -> RuntimeClient {
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

    private func request(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    func health() async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(for: request(path: "/v1/health"))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func setupStatus() async throws -> SetupStatus { try await value(path: "/v1/setup") }

    func connectOpenAI(key: String) async throws {
        _ = try await data(path: "/v1/setup/openai", method: "POST", body: ["apiKey": key])
    }

    func selectBackend(_ backend: String) async throws {
        _ = try await data(path: "/v1/setup/backend", method: "POST", body: ["backend": backend])
    }

    func startCodexLogin(mode: String) async throws -> CodexLoginStart {
        try await value(path: "/v1/setup/codex/login", method: "POST", body: ["mode": mode])
    }

    func codexLoginStatus(loginId: String) async throws -> CodexLoginResult {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        return try await value(path: "/v1/setup/codex/login/\(id)")
    }

    func cancelCodexLogin(loginId: String) async throws {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        _ = try await data(path: "/v1/setup/codex/login/\(id)/cancel", method: "POST")
    }

    func resumeLatest() async throws -> Transcript? {
        let sessions: SessionList = try await value(path: "/v1/sessions")
        guard let session = sessions.sessions.first else { return nil }
        let id = session.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.id
        return try await value(path: "/v1/sessions/\(id)/messages")
    }

    func events(text: String, sessionId: String?, requestId: String, fresh: Bool) -> AsyncThrowingStream<RuntimeEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(ChatRequest(text: text, sessionId: sessionId, requestId: requestId, fresh: fresh))
                    let (bytes, response) = try await URLSession.shared.bytes(for: try request(path: "/v1/chat", method: "POST", body: body))
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw RuntimeClientError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0, "Could not start response")
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: "),
                           let data = line.dropFirst(6).data(using: .utf8) {
                            continuation.yield(try JSONDecoder().decode(RuntimeEvent.self, from: data))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel(requestId: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["requestId": requestId])
        guard let request = try? request(path: "/v1/cancel", method: "POST", body: body) else { return }
        _ = try? await URLSession.shared.data(for: request)
    }

    private func data(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> Data {
        let encoded = try body.map { try JSONEncoder().encode($0) }
        let (data, response) = try await URLSession.shared.data(for: try request(path: path, method: method, body: encoded))
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
