import Foundation
import AgentClient
import AgentProtocol

func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }

func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, MockURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() {}

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
    private var chatProtocol: MockURLProtocol?
    private(set) var chatId = ""
    private(set) var cancelledId = ""

    var started: Bool { lock.withLock { chatProtocol != nil } }

    func start(id: String, protocolValue: MockURLProtocol) {
        lock.withLock {
            chatId = id
            chatProtocol = protocolValue
        }
    }

    func cancel(id: String) -> MockURLProtocol? {
        lock.withLock {
            cancelledId = id
            return chatProtocol
        }
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
        MockURLProtocol.handler = { request, protocolValue in
            let body = try! JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let requestId = body["requestId"] as! String
            if request.url?.path == "/v1/chat" {
                state.start(id: requestId, protocolValue: protocolValue)
                protocolValue.respond("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n", finish: false)
            } else {
                let chat = state.cancel(id: requestId)
                protocolValue.respond("{\"cancelled\":true}")
                chat?.respond("data: {\"type\":\"error\",\"message\":\"Interrupted\"}\n\n")
            }
        }
        let activeClient = client()
        let stream = try await activeClient.events(text: "hello", sessionId: nil, fresh: false)
        let collecting = Task { try await collect(stream) }
        for _ in 0..<100 where !state.started { try await Task.sleep(for: .milliseconds(10)) }
        check(state.started, "Agent client did not start its request")
        do {
            _ = try await activeClient.events(text: "again", sessionId: nil, fresh: false)
            preconditionFailure("Agent client accepted simultaneous responses")
        } catch {
            check(error.localizedDescription == "A response is already running.", "Agent busy-state check failed")
        }
        let cancelled = try await activeClient.cancel()
        let cancelledEvents = try await collecting.value
        check(cancelled, "Agent client did not cancel its active request")
        check(cancelledEvents == ["status", "error"], "Agent cancellation stream check failed")
        check(state.cancelledId == state.chatId, "Agent client cancellation used a different request ID")
        let cancelledAgain = try await activeClient.cancel()
        check(!cancelledAgain, "Agent client retained a completed request")
        print("Agent client check passed")
    }
}
