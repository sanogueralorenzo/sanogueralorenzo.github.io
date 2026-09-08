import Foundation

@MainActor
final class PiService {
    private var runner: PiProcess?
    private var checkedExecutable: URL?
    private let executableOverride: URL?
    private let now: () -> Date
    init(executable: URL? = nil, now: @escaping () -> Date = Date.init) {
        executableOverride = executable; self.now = now
    }
    private struct Session {
        let rpc: PiRPC
        let environment: PiEnvironment
        let provider: RewriteProvider
        let started: Date
    }
    private var session: Session?
    private var isRewriting = false
    private var pendingWarmup: RewriteProvider?
    var processIdentifier: Int32? { session?.rpc.isRunning == true ? session?.rpc.processIdentifier : nil }
    func cancel() {
        if isRewriting { shutdown() }
    }
    func shutdown() {
        pendingWarmup = nil
        preparation?.cancel(); preparationProvider = nil
        runner?.cancel()
        stopProcess()
    }
    private func stopProcess() {
        session?.rpc.stop(); session = nil
    }

    private func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL,
                     timeout: Double) async throws -> ProcessOutput {
        let runner = PiProcess(); self.runner = runner
        defer { if self.runner === runner { self.runner = nil } }
        return try await runner.run(executable: executable, arguments: arguments, environment: environment,
                                    directory: directory, timeout: timeout)
    }
    private func executable() async throws -> URL {
        guard let executable = executableOverride ?? CLIDiscovery.executable("pi") else {
            throw RewriteError.message("Install Pi, run pi in Terminal and use /login, then try again.")
        }
        if checkedExecutable != executable {
            let environment = try PiEnvironment(provider: "openai-codex", credential: "")
            defer { withExtendedLifetime(environment) {} }
            let result = try await run(executable, PiEnvironment.isolationArguments + ["--help"], environment: environment.environment, directory: environment.directory, timeout: 10)
            let help = String(decoding: result.stdout, as: UTF8.self)
            guard result.status == 0, (PiEnvironment.isolationArguments + ["--system-prompt", "--mode", "--thinking", "--extension"]).allSatisfy({ help.contains($0) }) else {
                throw RewriteError.message("Update Pi: this version lacks the isolation options Rewrite requires.")
            }
            checkedExecutable = executable
        }
        return executable
    }
    private func authenticatedEnvironment(_ executable: URL, provider: RewriteProvider) async throws -> PiEnvironment {
        var environment = CLIDiscovery.environment
        environment["PI_CODING_AGENT_DIR"] = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        // This dedicated Pi command does not load extensions, prompts, or custom model endpoints.
        // Credentials stay in memory and the private request directory, never logs or argv.
        let auth = try await run(executable, ["auth", "check", "--provider", provider.providerID, "--json", "--credentials"],
                                 environment: environment, directory: URL(fileURLWithPath: "/private/tmp"), timeout: 20)
        guard auth.status == 0, let json = try? JSONSerialization.jsonObject(with: auth.stdout) as? [String: Any],
              json["status"] as? String == "ready", let credential = json["credentials"] as? String,
              !credential.isEmpty, !credential.hasPrefix("!"), !credential.contains("\n") else {
            throw RewriteError.message("Sign in to \(provider.rawValue) in Pi: open pi in Terminal, use /login, then try again. Codex and Claude CLI sign-ins are not used.")
        }
        try Task.checkCancellation()
        return try PiEnvironment(provider: provider.providerID, credential: credential, oauth: json["authType"] as? String == "oauth")
    }
    // Launch and provider changes prepare without sending any selected text.
    func warmUp(_ provider: RewriteProvider) {
        guard !isRewriting else { pendingWarmup = provider; return }
        _ = readiness(provider)
    }
    private var preparation: Task<Void, Error>?
    private var preparationProvider: RewriteProvider?
    private var preparationID = UUID()

    private func readiness(_ provider: RewriteProvider) -> Task<Void, Error> {
        if let preparation, preparationProvider == provider,
           session.map({ $0.rpc.isRunning && now().timeIntervalSince($0.started) <= 180 }) ?? true {
            return preparation
        }
        let previous = preparation
        previous?.cancel()
        let id = UUID(); preparationID = id
        preparationProvider = provider
        let next = Task { @MainActor in
            _ = await previous?.result
            do {
                try Task.checkCancellation()
                try await self.prepare(provider)
                try Task.checkCancellation()
            } catch {
                self.stopProcess()
                if self.preparationID == id { self.preparationProvider = nil }
                throw error
            }
        }
        preparation = next
        return next
    }
    private func prepare(_ provider: RewriteProvider) async throws {
        // Refresh the short-lived auth snapshot well before its token can expire.
        // Healthy requests with the same provider reuse one process.
        if session.map({ $0.rpc.isRunning && $0.provider == provider && now().timeIntervalSince($0.started) <= 180 }) != true {
            stopProcess()
            let executable = try await executable(), environment = try await authenticatedEnvironment(executable, provider: provider)
            try Task.checkCancellation()
            let rpc = try PiRPC(executable: executable, arguments: environment.rewriteArguments(provider),
                            environment: environment.environment, directory: environment.directory)
            session = Session(rpc: rpc, environment: environment, provider: provider, started: now())
        }
    }
    func rewrite(_ source: String, provider: RewriteProvider) async throws -> String {
        guard !isRewriting else { throw RewriteError.message("A rewrite is already finishing. Try again in a moment.") }
        isRewriting = true
        defer {
            isRewriting = false
            if let provider = pendingWarmup {
                pendingWarmup = nil; warmUp(provider)
            }
        }
        do {
            try await readiness(provider).value
            try Task.checkCancellation()
            guard let rpc = session?.rpc else { throw RewriteError.message("Pi could not start. Try again.") }
            try await rpc.resetSession()
            try Task.checkCancellation()
            let output = try await rpc.send("prompt", message: source)
            let result = try Self.parse(output)
            // Clear text immediately after completion, not only before the next request.
            try await rpc.resetSession()
            try Task.checkCancellation()
            return result
        } catch {
            let pending = pendingWarmup
            shutdown()
            pendingWarmup = pending
            throw error
        }
    }
    static func parse(_ data: Data) throws -> String {
        let failure = RewriteError.message("Pi did not return a completed rewrite. Check your Pi sign-in, then retry.")
        var result: String?, completed = false
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") where !line.isEmpty {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = event["type"] as? String else { throw failure }
            if type.hasPrefix("tool_execution") || type == "error" { throw failure }
            if type == "message_end", let message = event["message"] as? [String: Any], message["role"] as? String == "assistant" {
                guard result == nil, message["stopReason"] as? String == "stop",
                      let content = message["content"] as? [[String: Any]],
                      content.allSatisfy({ ["text", "thinking"].contains($0["type"] as? String ?? "") }) else { throw failure }
                result = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            }
            if type == "agent_end" { guard result != nil else { throw failure }; completed = true }
        }
        guard completed, let result else { throw failure }
        return result
    }
}
