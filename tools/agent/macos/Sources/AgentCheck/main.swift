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
            headerFields: [
                "Content-Type": stream ? "text/event-stream" : "application/json",
                "X-Agent-Stream": stream ? "snapshot" : ""
            ]
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

    static func collectRun(_ stream: EventStream) async throws -> [String] {
        var types: [String] = []
        for try await envelope in stream {
            types.append(envelope.event.type)
            if envelope.event.isTerminal { break }
        }
        return types
    }

    static func main() async throws {
        let request = try JSONEncoder().encode(ChatRequest(text: "hello", sessionId: "s1"))
        check(String(decoding: request, as: UTF8.self).contains("\"sessionId\":\"s1\""), "Agent protocol check failed")
        let artifact = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"artifact","artifact":{"id":"a1","kind":"image","name":"result.png","path":"/tmp/result.png"}}"#.utf8))
        check(artifact.artifact?.name == "result.png", "Agent artifact protocol check failed")
        let navigation = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"navigate","url":"agent://sessions/s1","continues":true,"session":{"id":"s1","title":"Runtime reconnects"}}"#.utf8))
        check(navigation.session?.title == "Runtime reconnects" && navigation.continues == true, "Agent navigation protocol check failed")
        let entry = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"home_entry","entry":{"id":"e1","sessionId":"s1","title":"Fix tests","body":"Fix the tests","requests":[{"text":"Fix the tests","createdAt":"2026-09-22T00:00:00Z"}],"state":"ready","summary":"Tests pass.","url":"agent://sessions/s1","updatedAt":"2026-09-22T00:00:00Z"}}"#.utf8))
        check(entry.entry?.summary == "Tests pass." && entry.entry?.requests.first?.text == "Fix the tests", "Agent Home entry protocol check failed")
        let removedEntry = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"home_entry_removed","id":"e1"}"#.utf8))
        check(removedEntry.id == "e1", "Agent Home entry removal protocol check failed")
        let queue = try JSONDecoder().decode(RuntimeEvent.self, from: Data(#"{"type":"queue","tasks":[{"id":"q1","sessionId":"s1","text":"Next","channel":"macos","createdAt":"2026-09-22T00:00:00Z"}]}"#.utf8))
        check(queue.tasks?.first?.text == "Next", "Agent queued follow-up protocol check failed")
        let setup = try JSONDecoder().decode(SetupStatus.self, from: Data(#"{"configured":true,"authMode":"apiKey","codex":{"installed":true,"connected":true}}"#.utf8))
        check(setup.codex.connected, "Agent setup protocol check failed")
        check(setup.authMode == "apiKey", "Agent API-key setup protocol check failed")
        MockURLProtocol.handler = { request, protocolValue in
            check(request.url?.path == "/v1/events" && request.url?.query == "sessionId=s1", "Agent live event URL check failed")
            protocolValue.respond("""
            data: {"sessionId":"s1","runId":"","event":{"type":"snapshot","snapshot":{"sessions":[],"homeEntries":[],"queuedTasks":[],"transcript":null,"activeRuns":[],"lastRuns":[]}}}

            data: {"sessionId":"s1","runId":"r1","event":{"type":"turn","text":"hello","channel":"macos","hasAttachments":false}}

            data: {"sessionId":"s1","runId":"r1","event":{"type":"done","sessionId":"s1"}}

            """, stream: true)
        }
        let completed = try await collectRun(try await client().events(sessionId: "s1"))
        check(completed == ["snapshot", "turn", "done"], "Agent shared stream check failed")

        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"sessionId\":\"s1\",\"runId\":\"\",\"event\":{\"type\":\"navigate\",\"url\":\"agent://sessions/s2\",\"session\":{\"id\":\"s2\",\"title\":\"Saved work\"}}}\n\n", stream: true)
        }
        var redirected = try await client().events(sessionId: "s1").makeAsyncIterator()
        let redirectEvent = try await redirected.next()
        check(redirectEvent?.event.session?.id == "s2", "Agent session redirect check failed")

        MockURLProtocol.handler = { request, protocolValue in
            check(request.url?.query == "sessionId=s1&runId=r1", "Agent handoff reconnect URL check failed")
            protocolValue.respond("data: {\"sessionId\":\"s1\",\"runId\":\"r1\",\"event\":{\"type\":\"navigate\",\"continues\":true,\"url\":\"agent://sessions/s2\",\"session\":{\"id\":\"s2\",\"title\":\"Saved work\"}}}\n\n", stream: true)
        }
        var handoff = try await client().events(sessionId: "s1", runId: "r1").makeAsyncIterator()
        let handoffEvent = try await handoff.next()
        check(handoffEvent?.event.continues == true, "Agent handoff reconnect check failed")

        MockURLProtocol.handler = { _, protocolValue in protocolValue.respond("data: {broken}\n\n", stream: true) }
        do {
            _ = try await collectRun(try await client().events(sessionId: "s1"))
            preconditionFailure("Agent accepted a malformed event")
        } catch {
            check(error.localizedDescription == "Agent runtime sent an invalid event.", "Agent malformed-event check failed")
        }

        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"sessionId\":\"s1\",\"runId\":\"\",\"event\":{\"type\":\"snapshot\",\"snapshot\":{\"sessions\":[],\"homeEntries\":[],\"queuedTasks\":[],\"transcript\":null,\"activeRuns\":[],\"lastRuns\":[]}}}\n\n", stream: true)
        }
        do {
            for try await _ in try await client().events(sessionId: "s1") {}
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
                protocolValue.respond(busy ? #"{"error":"busy"}"# : #"{"run":{"id":"r1","sessionId":"s1","origin":"macos"}}"#, status: busy ? 409 : 202)
            case ("POST", "/v1/runs/stop"):
                protocolValue.respond(#"{"stopped":true}"#)
            case ("POST", "/v1/follow-ups"), ("POST", "/v1/follow-ups/remove"):
                protocolValue.respond(#"{"task":{"id":"q1","sessionId":"s1","text":"Next","channel":"macos","createdAt":"2026-09-22T00:00:00Z"}}"#)
            case ("POST", "/v1/follow-ups/steer"):
                protocolValue.respond(#"{"steered":true}"#)
            default:
                protocolValue.respond("{}", status: 404)
            }
        }
        let apiClient = client()
        let submitted = try await apiClient.submit(text: "hello", sessionId: "s1")
        check(submitted?.id == "r1", "Agent submit check failed")
        let busy = try await apiClient.submit(text: "busy", sessionId: "s1")
        check(busy == nil, "Agent busy check failed")
        let didStop = try await apiClient.stop(runId: "r1")
        check(didStop, "Agent stop check failed")
        let queued = try await apiClient.queue(text: "Next", sessionId: "s1")
        check(queued.id == "q1", "Agent queue check failed")
        let removed = try await apiClient.removeQueued(taskId: queued.id, sessionId: "s1")
        check(removed.text == "Next", "Agent remove follow-up check failed")
        let steered = try await apiClient.steerQueued(taskId: queued.id, sessionId: "s1", runId: "r1")
        check(steered, "Agent steer follow-up check failed")
        MockURLProtocol.handler = { request, protocolValue in
            if request.url?.path == "/v1/sessions/auto" {
                protocolValue.respond(#"{"session":{"id":"s1","title":"Saved work"}}"#)
            } else {
                check(request.url?.path == "/v1/sessions", "Agent session list URL check failed")
                protocolValue.respond(#"{"sessions":[{"id":"s1","title":"Saved work","activeRunId":null}]}"#)
            }
        }
        let selectedSession = try await apiClient.openSession(preferredSessionId: "s1")
        check(selectedSession.id == "s1", "Agent session selection check failed")
        let listedSessions = try await apiClient.sessions()
        check(listedSessions.first?.id == "s1", "Agent session list check failed")
        let stopped = Mutex(false)
        MockURLProtocol.handler = { _, protocolValue in
            protocolValue.respond("data: {\"sessionId\":\"s1\",\"runId\":\"\",\"event\":{\"type\":\"snapshot\",\"snapshot\":{\"sessions\":[],\"homeEntries\":[],\"queuedTasks\":[],\"transcript\":null,\"activeRuns\":[],\"lastRuns\":[]}}}\n\n", stream: true, finish: false)
        }
        MockURLProtocol.stopped = { stopped.withLock { $0 = true } }
        var stream: EventStream? = try await client().events(sessionId: "s1")
        for try await _ in stream! { break }
        stream = nil
        for _ in 0..<100 where !stopped.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        check(stopped.withLock { $0 }, "Agent observer did not close its HTTP stream")
        print("Agent checks passed")
    }
}
