import Foundation

@MainActor
extension RewriteTests {
    static func piService() async throws {
        let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/pi_fixture.py")
        var clock = Date()
        let fixture = PiService(executable: fixtureURL, now: { clock })
        fixture.warmUp(RewriteConfiguration(kind: .openai))
        for _ in 0..<200 where fixture.processIdentifier == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let warmPreparation = fixture.processIdentifier
        check(warmPreparation != nil, "launch warmup starts a process without sending text")
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) == "She went to the library yesterday.", "Pi subprocess auth, isolation, stdin and completed replacement result")
        let firstPID = fixture.processIdentifier
        check(firstPID == warmPreparation, "rewrite waits for service-owned launch preparation")
        fixture.cancel() // Idle cancellation must not discard the warmed process.
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) == "She went to the library yesterday." && firstPID == fixture.processIdentifier, "RPC reuses process and starts a fresh session")
        clock = clock.addingTimeInterval(181)
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) == "She went to the library yesterday." && fixture.processIdentifier != firstPID, "credentials refresh after three minutes from startup")
        let refreshedPID = fixture.processIdentifier
        fixture.warmUp(RewriteConfiguration(kind: .anthropic))
        fixture.warmUp(RewriteConfiguration(kind: .openai))
        fixture.warmUp(RewriteConfiguration(kind: .anthropic))
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .anthropic)) == "She went to the library yesterday." && fixture.processIdentifier != refreshedPID, "rapid provider warmups serialize and use the final provider")
        fixture.shutdown()
        fixture.warmUp(RewriteConfiguration(kind: .openai))
        let cancelledWarmup = Task {
            try await fixture.rewrite("must never reach the fixture", action: .grammar, configuration: RewriteConfiguration(kind: .openai))
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        cancelledWarmup.cancel(); fixture.cancel()
        do { _ = try await cancelledWarmup.value; fatalError("FAIL warmup cancellation") }
        catch { check(error is CancellationError, "cancellation during warmup never sends a prompt") }
        do {
            _ = try await fixture.rewrite("must never reach the fixture", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) {
                check(fixture.processIdentifier != nil, "selection validation runs after Pi preparation")
                throw RewriteError.message("selection changed")
            }
            fatalError("FAIL selection preflight")
        } catch { check(error.localizedDescription == "selection changed", "selection revalidated before prompt") }
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) == "She went to the library yesterday.", "service recovers after rejected delivery")
        var activePID: Int32?
        _ = try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .openai)) {
            activePID = fixture.processIdentifier
            fixture.warmUp(RewriteConfiguration(kind: .anthropic))
        }
        for _ in 0..<200 {
            if let pid = fixture.processIdentifier, pid != activePID { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        check(fixture.processIdentifier != nil && fixture.processIdentifier != activePID, "settings warmup waits until the active rewrite completes")
        check(try await fixture.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: .anthropic)) == "She went to the library yesterday.", "queued provider configuration is ready for the next rewrite")
        fixture.shutdown()
    }
    static func livePi() async throws {
        let kind: RewriteProvider = CommandLine.arguments.contains("anthropic") ? .anthropic : .openai
        let service = PiService()
        defer { service.shutdown() }
        service.warmUp(RewriteConfiguration(kind: kind))
        var pid: Int32? = service.processIdentifier
        for _ in 0..<2 {
            let started = Date()
            let result = try await service.rewrite("She go to the library yesterday.", action: .grammar, configuration: RewriteConfiguration(kind: kind))
            check(result.contains("went") && !result.contains("She go"), "live grammar")
            if let pid { check(pid == service.processIdentifier, "live RPC process reused") }
            pid = service.processIdentifier
            print("PASS: live Pi rewrite in \(String(format: "%.2f", Date().timeIntervalSince(started))) seconds; process \(pid ?? 0)")
            service.cancel()
        }
    }
    static func installedPi() async throws {
        guard let executable = CLIDiscovery.executable("pi") else { fatalError("Pi missing") }
        let request = try PiRequest(provider: "openai-codex", credential: "disposable-fixture-token", oauth: true)
        let output = try await ProcessRunner().run(executable: executable, arguments: PiService.isolationArguments + ["--list-models"], environment: request.environment, directory: request.directory, timeout: 20)
        check(output.status == 0 && String(decoding: output.stdout, as: UTF8.self).contains("gpt-5.6-luna"), "installed Pi exposes Luna in an isolated configuration")
        print("PASS installed Pi isolated model discovery; no inference or real credentials")
    }
}
