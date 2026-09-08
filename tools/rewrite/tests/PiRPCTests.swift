import Foundation

@MainActor
extension RewriteTests {
    static func piResponses() async throws {
        func stream(_ content: [[String: Any]], reason: String = "stop", completed: Bool = true) throws -> Data {
            let message: [String: Any] = ["type": "message_end", "message": ["role": "assistant", "stopReason": reason, "content": content]]
            var data = try JSONSerialization.data(withJSONObject: message)
            if completed { data.append(Data("\n{\"type\":\"agent_end\"}\n".utf8)) }
            return data
        }
        let text: [[String: Any]] = [["type": "text", "text": "Hello.\n"]]
        check(try PiService.parse(stream(text)) == "Hello.\n", "Pi completed response and whitespace")
        check(try PiService.parse(stream([["type": "thinking", "thinking": "private" ]] + text)) == "Hello.\n", "thinking excluded from replacement")
        check(try PiService.parse(stream([["type": "text", "text": "A\u{2028}B"]])) == "A\u{2028}B", "Unicode line separator preserved")
        rejects("partial Pi response") { _ = try PiService.parse(stream(text, completed: false)) }
        for reason in ["length", "error", "aborted", "toolUse"] {
            rejects("unfinished stop reason " + reason) { _ = try PiService.parse(stream(text, reason: reason)) }
        }
        rejects("tool content") { _ = try PiService.parse(stream([["type": "toolCall", "name": "bash"]] + text)) }
        rejects("tool event") { _ = try PiService.parse(Data("{\"type\":\"tool_execution_start\"}\n".utf8) + stream(text)) }
        rejects("invalid output") { _ = try PiService.parse(Data("not JSON\n".utf8) + stream(text)) }
        rejects("multiple assistant results") { _ = try PiService.parse(stream(text, completed: false) + Data("\n".utf8) + stream(text)) }
    }
    static func piRPC() async throws {
        func rpcFixture(_ scenario: String) throws -> PiRPC {
            try PiRPC(executable: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/rpc_fixture.py"), arguments: [scenario], environment: CLIDiscovery.environment, directory: URL(fileURLWithPath: "/private/tmp"))
        }
        let rpc = try rpcFixture("success")
        _ = try await rpc.send("new_session", timeout: 2)
        check(try PiService.parse(await rpc.send("prompt", message: "fixture", timeout: 2)) == "Hello\u{2028}world.", "RPC fragmented JSONL, Unicode separator, stale IDs and completion before ack")
        rpc.stop()
        for scenario in ["crash", "timeout", "overflow", "tool", "cancelled-reset"] {
            let rpc = try rpcFixture(scenario)
            do {
                _ = try await rpc.send(scenario == "cancelled-reset" ? "new_session" : "prompt", message: "fixture", timeout: scenario == "timeout" ? 0.1 : 2)
                fatalError("FAIL RPC " + scenario)
            } catch { passed += 1 }
            rpc.stop()
        }
        let dirtyRPC = try rpcFixture("dirty-reset")
        do { try await dirtyRPC.resetSession(); fatalError("FAIL dirty session accepted") }
        catch { passed += 1 }
        dirtyRPC.stop()
        let cancelledRPC = try rpcFixture("timeout")
        let cancelledTask = Task { try await cancelledRPC.send("prompt", message: "fixture", timeout: 2) }
        try await Task.sleep(nanoseconds: 100_000_000)
        cancelledTask.cancel()
        do { _ = try await cancelledTask.value; fatalError("FAIL RPC cancellation") }
        catch { check(error is CancellationError, "RPC cancellation resumes pending request") }
        cancelledRPC.stop()
    }
}
