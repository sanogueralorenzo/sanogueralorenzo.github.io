import Foundation
import Synchronization
import AgentClient
import AgentProtocol

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, MockURLProtocol) -> Void)?
    nonisolated(unsafe) static var stopped: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() { Self.stopped?() }

    func respond(_ body: String, status: Int = 200, stream: Bool = false, finish: Bool = true) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
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

    static func collectRun(_ stream: AsyncThrowingStream<RunEnvelope, Error>) async throws -> [String] {
        var types: [String] = []
        for try await envelope in stream {
            types.append(envelope.event.type)
            if envelope.event.isTerminal { break }
        }
        return types
    }

    static func main() async throws {
        let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: nil, fresh: true))
        check(String(decoding: request, as: UTF8.self).contains("\"fresh\":true"), "Agent protocol check failed")
        let artifact = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"artifact","artifact":{"id":"a1","kind":"image","name":"result.png","path":"/tmp/result.png"}}"#.utf8))
        check(artifact.artifact?.name == "result.png", "Agent artifact protocol check failed")
        let setup = try JSONDecoder().decode(SetupStatus.self, from: Data(#"{"configured":false,"openAIConfigured":false,"codex":{"installed":true,"connected":true}}"#.utf8))
        check(setup.codex.connected, "Agent setup protocol check failed")

        MockURLProtocol.handler = { request, protocolValue in
            check(request.url?.path == "/v1/events" && request.url?.query == nil, "Agent live event URL check failed")
            protocolValue.respond("""
            data: {"runId":"r1","event":{"type":"turn","text":"hello","channel":"cli","hasAttachments":false}}

            data: {"runId":"r1","event":{"type":"done","sessionId":"s1"}}

            """, stream: true)
        }
        let completed = try await collectRun(try await client().events())
        check(completed == ["turn", "done"], "Agent shared stream check failed")

        MockURLProtocol.handler = { _, protocolValue in protocolValue.respond("data: {broken}\n\n", stream: true) }
        do {
            _ = try await collectRun(try await client().events())
            preconditionFailure("Agent accepted a malformed event")
        } catch {
            check(error.localizedDescription == "Agent runtime sent an invalid event.", "Agent malformed-event check failed")
        }

        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"runId\":\"r1\",\"event\":{\"type\":\"status\",\"message\":\"Working\"}}\n\n", stream: true)
        }
        do {
            for try await _ in try await client().events() {}
            preconditionFailure("Agent accepted a disconnected observer")
        } catch {
            check(error.localizedDescription == "Agent runtime disconnected.", "Agent disconnect check failed")
        }

        let submissions = Mutex(0)
        MockURLProtocol.handler = { request, protocolValue in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/runs"):
                let busy = submissions.withLock { count in
                    count += 1
                    return count > 1
                }
                protocolValue.respond(busy ? #"{"error":"busy"}"# : #"{"run":{"id":"r1","origin":"macos"}}"#, status: busy ? 409 : 202)
            case ("POST", "/v1/runs/stop"):
                protocolValue.respond(#"{"stopped":true}"#)
            default:
                protocolValue.respond("{}", status: 404)
            }
        }
        let apiClient = client()
        let submitted = try await apiClient.submit(text: "hello", sessionId: nil, fresh: false)
        check(submitted?.id == "r1", "Agent submit check failed")
        let busy = try await apiClient.submit(text: "busy", sessionId: nil, fresh: false)
        check(busy == nil, "Agent busy check failed")
        let didStop = try await apiClient.stop()
        check(didStop, "Agent stop check failed")

        let stopped = Mutex(false)
        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"runId\":\"r1\",\"event\":{\"type\":\"turn\",\"text\":\"hello\",\"channel\":\"api\",\"hasAttachments\":false}}\n\n", stream: true, finish: false)
        }
        MockURLProtocol.stopped = { stopped.withLock { $0 = true } }
        var stream: AsyncThrowingStream<RunEnvelope, Error>? = try await client().events()
        for try await _ in stream! { break }
        stream = nil
        for _ in 0..<100 where !stopped.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        check(stopped.withLock { $0 }, "Agent observer did not close its HTTP stream")
        print("Agent checks passed")
    }
}
