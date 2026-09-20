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
    let homeDirectory: URL

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
        let path = homeDirectory.appending(path: "runtime.json")
        guard let data = try? Data(contentsOf: path) else { throw RuntimeClientError.notRunning }
        let discovery = try JSONDecoder().decode(RuntimeDiscovery.self, from: data)
        guard discovery.protocolVersion == 1 else { throw RuntimeClientError.incompatible }
        return RuntimeClient(homeDirectory: homeDirectory)
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let data = try Data(contentsOf: homeDirectory.appending(path: "runtime.json"))
        let discovery = try JSONDecoder().decode(RuntimeDiscovery.self, from: data)
        guard discovery.protocolVersion == 1,
              let baseURL = URL(string: "http://127.0.0.1:\(discovery.port)") else {
            throw RuntimeClientError.incompatible
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(discovery.token)", forHTTPHeaderField: "Authorization")
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

    func setupStatus() async throws -> SetupStatus {
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup"))
        try check(response, data: data)
        return try JSONDecoder().decode(SetupStatus.self, from: data)
    }

    func connectOpenAI(key: String) async throws {
        let body = try JSONEncoder().encode(APIKeyRequest(apiKey: key))
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup/openai", method: "POST", body: body))
        try check(response, data: data)
    }

    func selectBackend(_ backend: String) async throws {
        let body = try JSONEncoder().encode(BackendRequest(backend: backend))
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup/backend", method: "POST", body: body))
        try check(response, data: data)
    }

    func startCodexLogin(mode: String) async throws -> CodexLoginStart {
        let body = try JSONEncoder().encode(CodexLoginRequest(mode: mode))
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup/codex/login", method: "POST", body: body))
        try check(response, data: data)
        return try JSONDecoder().decode(CodexLoginStart.self, from: data)
    }

    func codexLoginStatus(loginId: String) async throws -> CodexLoginResult {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup/codex/login/\(id)"))
        try check(response, data: data)
        return try JSONDecoder().decode(CodexLoginResult.self, from: data)
    }

    func cancelCodexLogin(loginId: String) async throws {
        let id = loginId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginId
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/setup/codex/login/\(id)/cancel", method: "POST"))
        try check(response, data: data)
    }

    func resumeLatest() async throws -> Transcript? {
        let (listData, listResponse) = try await URLSession.shared.data(for: try request(path: "/v1/sessions"))
        try check(listResponse, data: listData)
        guard let session = try JSONDecoder().decode(SessionList.self, from: listData).sessions.first else { return nil }
        let id = session.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.id
        let (data, response) = try await URLSession.shared.data(for: try request(path: "/v1/sessions/\(id)/messages"))
        try check(response, data: data)
        return try JSONDecoder().decode(Transcript.self, from: data)
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
                            continuation.yield(try JSONDecoder().decode(RuntimeEnvelope.self, from: data).event)
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

    private func check(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RuntimeClientError.badResponse(status, String(decoding: data, as: UTF8.self))
        }
    }
}
