import Foundation

@MainActor
private final class PiFixture {
    let directory: URL
    let executable: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rewrite-core-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        executable = directory.appendingPathComponent("pi.py")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "tests/pi.py"), to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try mode("normal")
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func mode(_ name: String) throws { try name.write(to: directory.appendingPathComponent("mode"), atomically: true, encoding: .utf8) }
    var events: [[String: Any]] {
        let data = (try? Data(contentsOf: directory.appendingPathComponent("events.jsonl"))) ?? Data()
        return data.split(separator: 10).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }
    func count(_ event: String) -> Int { events.filter { $0["event"] as? String == event }.count }
    func cleaned() throws {
        for event in events where event["event"] as? String == "started" {
            try expect(!FileManager.default.fileExists(atPath: event["directory"] as! String), "Temporary credentials survived shutdown")
        }
    }
}

@MainActor
enum PiTests {
    static let provider = RewriteProvider.openai

    static func lifecycle() async throws {
        let fixture = try PiFixture()
        var clock = Date()
        let service = PiService(executable: fixture.executable, now: { clock })
        defer { service.shutdown() }
        service.warmUp(provider)
        try await eventually("Warmup did not prepare Pi") { fixture.count("state") > 0 }
        try expect(fixture.count("prompt") == 0, "Warmup sent text")
        let pid = service.processIdentifier
        for source in ["First 🦊\n\"selection\"", "Second selection"] {
            let result = try await service.rewrite(source, action: .shorter, provider: provider)
            try expect(result == "Edited: " + source, "Response or source data was changed")
            try expect(service.processIdentifier == pid, "Healthy process was restarted")
            try expect(fixture.events.last?["clean"] as? Bool == true, "Request text was not cleared")
        }
        service.cancel()
        try expect(service.processIdentifier == pid, "Idle cancellation discarded the warm process")
        clock = clock.addingTimeInterval(181)
        _ = try await service.rewrite("Expired credential", action: .grammar, provider: provider)
        try expect(service.processIdentifier != pid, "Three-minute credential refresh did not restart Pi")
        let refreshed = service.processIdentifier
        _ = try await service.rewrite("Other provider", action: .clearer, provider: RewriteProvider.anthropic)
        try expect(service.processIdentifier != refreshed, "Provider change reused the wrong process")
        try expect(fixture.events.contains { $0["provider"] as? String == "anthropic" }, "Anthropic contract not exercised")
        service.shutdown()
        try fixture.cleaned()
    }

    static func cancellation() async throws {
        let fixture = try PiFixture(), service = PiService(executable: fixture.executable)
        defer { service.shutdown() }
        try fixture.mode("hold")
        let task = Task { try await service.rewrite("Cancel this", action: .grammar, provider: provider) }
        defer { task.cancel() }
        try await eventually("Fixture never received the request") { fixture.count("prompt") == 1 }
        let pid = service.processIdentifier!
        task.cancel(); service.cancel()
        try await expectFailure({ $0 is CancellationError }) { _ = try await task.value }
        try await eventually("Cancelled child is still running") { kill(pid, 0) != 0 && errno == ESRCH }
        try expect(fixture.count("prompt") == 1, "Cancellation retried the request")
        try fixture.cleaned()
    }

    static func failures() async throws {
        for (mode, reason) in [("invalid", "invalid response"), ("tool", "unexpected action"), ("partial", "completed rewrite"), ("dirty", "clear the previous rewrite")] {
            let fixture = try PiFixture(), service = PiService(executable: fixture.executable)
            defer { service.shutdown() }
            try fixture.mode(mode)
            try await expectFailure(messageContains(reason)) {
                _ = try await service.rewrite("Bad response", action: .grammar, provider: provider)
            }
            try expect(fixture.count("started") == 1, "Failure was not exercised against a running fixture")
            try expect(fixture.count("prompt") == (mode == "dirty" ? 0 : 1), "Failure sent or retried unexpected text")
            try expect(service.processIdentifier == nil, "Failed process was retained")
            try fixture.cleaned()
            try fixture.mode("normal")
            let result = try await service.rewrite("Recovery", action: .grammar, provider: provider)
            try expect(result == "Edited: Recovery", "Next explicit rewrite did not recover")
        }
    }

    static func timeout() async throws {
        let fixture = try PiFixture()
        let request = try PiRequest(provider: "openai-codex", credential: "test-access-token", oauth: true)
        defer { withExtendedLifetime(request) {} }
        let rpc = try PiRPC(executable: fixture.executable, arguments: request.rewriteArguments(provider), environment: request.environment, directory: request.directory)
        defer { rpc.stop() }
        try await rpc.resetSession()
        try fixture.mode("hold")
        try await expectFailure(messageContains("timed out")) {
            _ = try await rpc.send("prompt", message: Editing.payload("Timeout", action: .grammar), timeout: 0.5)
        }
        try expect(fixture.count("prompt") == 1, "Timeout occurred before the request reached Pi")
        try await eventually("Timed-out Pi is still running") { !rpc.isRunning }
    }
}
