import Foundation
import AgentClient
import AgentProtocol

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, MockURLProtocol) -> Void)?
    nonisolated(unsafe) static var stopped: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() { Self.stopped?() }

    func respond(_ body: String, status: Int = 200, finish: Bool = true) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    private var wasStopped = false

    var started: Bool { lock.withLock { didStart } }
    var stopped: Bool { lock.withLock { wasStopped } }

    func start() {
        lock.withLock { didStart = true }
    }

    func stop() {
        lock.withLock { wasStopped = true }
    }
}

@main
struct AgentClientCheck {
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
        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("""
            data: {"type":"text_delta","delta":"hello"}

            data: {"type":"done","sessionId":"s1"}

            """)
        }
        let completed = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
        check(completed == ["text_delta", "done"], "Agent client stream check failed")

        MockURLProtocol.handler = { _, protocolValue in protocolValue.respond("data: {broken}\n\n") }
        do {
            _ = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
            preconditionFailure("Agent client accepted a malformed event")
        } catch {
            check(error.localizedDescription == "Agent runtime sent an invalid event.", "Agent malformed-event check failed")
        }

        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n")
        }
        do {
            _ = try await collect(try await client().events(text: "hello", sessionId: nil, fresh: false))
            preconditionFailure("Agent client accepted a stream without a terminal event")
        } catch {
            check(error.localizedDescription == "Agent runtime disconnected before the response completed.", "Agent disconnect check failed")
        }

        let state = RequestState()
        MockURLProtocol.handler = { _, protocolValue in
            state.start()
            protocolValue.respond("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n", finish: false)
        }
        MockURLProtocol.stopped = { state.stop() }
        let activeClient = client()
        let stream = try await activeClient.events(text: "hello", sessionId: nil, fresh: false)
        let collecting = Task {
            do {
                _ = try await collect(stream)
                return false
            } catch {
                return true
            }
        }
        for _ in 0..<100 where !state.started { try await Task.sleep(for: .milliseconds(10)) }
        check(state.started, "Agent client did not start its request")
        do {
            _ = try await activeClient.events(text: "again", sessionId: nil, fresh: false)
            preconditionFailure("Agent client accepted simultaneous responses")
        } catch {
            check(error.localizedDescription == "A response is already running.", "Agent busy-state check failed")
        }
        let cancelled = await activeClient.cancel()
        let cancellationFinished = await collecting.value
        check(cancelled, "Agent client did not cancel its active request")
        check(cancellationFinished && state.stopped, "Agent cancellation stream check failed")
        let cancelledAgain = await activeClient.cancel()
        check(!cancelledAgain, "Agent client retained a completed request")
        print("Agent client check passed")
    }
}
