import Foundation
import AgentClient
import AgentProtocol

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((MockURLProtocol) -> Void)?
    nonisolated(unsafe) static var stopped: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() { Self.stopped?() }

    func respond(_ body: String, finish: Bool = true) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = (started: false, stopped: false)

    var started: Bool { lock.withLock { value.started } }
    var stopped: Bool { lock.withLock { value.stopped } }
    func start() { lock.withLock { value.started = true } }
    func stop() { lock.withLock { value.stopped = true } }
}

@main
struct AgentCheck {
    static func client() -> RuntimeClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return RuntimeClient(
            baseURL: URL(string: "http://127.0.0.1:1")!,
            token: "test-token",
            session: URLSession(configuration: configuration)
        )
    }

    static func collect(_ stream: AsyncThrowingStream<RuntimeEvent, Error>) async throws -> [String] {
        var types: [String] = []
        for try await event in stream { types.append(event.type) }
        return types
    }

    static func main() async throws {
        let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: nil, fresh: true))
        check(String(decoding: request, as: UTF8.self).contains("\"fresh\":true"), "Agent protocol check failed")
        let artifact = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"artifact","artifact":{"id":"a1","kind":"image","name":"result.png","mimeType":"image/png","size":12,"path":"/tmp/result.png"}}"#.utf8))
        check(artifact.artifact?.name == "result.png", "Agent artifact protocol check failed")
        let setup = try JSONDecoder().decode(SetupStatus.self, from: Data(#"{"configured":false,"selectedBackend":null,"openAIConfigured":false,"codex":{"installed":true,"connected":true,"planType":"plus"}}"#.utf8))
        check(setup.codex.connected, "Agent setup protocol check failed")
        let login = try JSONDecoder().decode(CodexLoginStart.self, from: Data(#"{"type":"chatgpt","loginId":"login-1","authUrl":"https://auth.openai.com/fake"}"#.utf8))
        check(login.loginId == "login-1" && login.authUrl?.hasPrefix("https://") == true, "Agent login protocol check failed")

        MockURLProtocol.handler = { protocolValue in
            protocolValue.respond("""
            data: {"type":"text_delta","delta":"hello"}

            data: {"type":"done","sessionId":"s1"}

            """)
        }
        let completed = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
        check(completed == ["text_delta", "done"], "Agent stream check failed")

        MockURLProtocol.handler = { $0.respond("data: {broken}\n\n") }
        do {
            _ = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
            preconditionFailure("Agent accepted a malformed event")
        } catch {
            check(error.localizedDescription == "Agent runtime sent an invalid event.", "Agent malformed-event check failed")
        }

        MockURLProtocol.handler = { $0.respond("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n") }
        do {
            _ = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
            preconditionFailure("Agent accepted an interrupted stream")
        } catch {
            check(error.localizedDescription == "Agent runtime disconnected before the response completed.", "Agent interruption check failed")
        }

        let state = RequestState()
        MockURLProtocol.handler = { protocolValue in
            state.start()
            protocolValue.respond("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n", finish: false)
        }
        MockURLProtocol.stopped = { state.stop() }
        let activeClient = client()
        let stream = try await activeClient.events(text: "hello", sessionId: nil, fresh: false)
        let collecting = Task { (try? await collect(stream)) == nil }
        for _ in 0..<100 where !state.started { try await Task.sleep(for: .milliseconds(10)) }
        check(state.started, "Agent client did not start its request")
        do {
            _ = try await activeClient.events(text: "again", sessionId: nil, fresh: false)
            preconditionFailure("Agent accepted simultaneous responses")
        } catch {
            check(error.localizedDescription == "A response is already running.", "Agent busy-state check failed")
        }
        let cancelled = await activeClient.cancel()
        let cancellationFinished = await collecting.value
        check(cancelled, "Agent did not cancel its active request")
        check(cancellationFinished && state.stopped, "Agent cancellation check failed")
        let cancelledAgain = await activeClient.cancel()
        check(!cancelledAgain, "Agent retained a completed request")
        print("Agent checks passed")
    }
}
