import Foundation

enum ProcessorKind: String, CaseIterable {
    case openai = "OpenAI", anthropic = "Anthropic"
    var providerID: String { self == .openai ? "openai-codex" : "anthropic" }
    var notice: String { "Uses your Pi sign-in. Selected text is sent to \(rawValue)." }
    var preferredModel: String { self == .openai ? "gpt-5.6-luna" : "claude-haiku-4-5-20251001" }
    static func saved(_ value: String?) -> ProcessorKind? {
        switch value {
        case "Codex CLI": return .openai
        case "Claude CLI": return .anthropic
        default: return value.flatMap(Self.init(rawValue:))
        }
    }
    func modelID(_ value: String) -> String {
        if self == .openai && value == "GPT 5.6 Luna · Light reasoning" { return preferredModel }
        if value.isEmpty || value == "default" || value == modelLabel(preferredModel) { return preferredModel }
        return value
    }
    func modelLabel(_ value: String) -> String {
        if value == preferredModel { return self == .openai ? "GPT 5.6 Luna · Reasoning off · Priority" : "Claude Haiku 4.5 · Thinking off" }
        return value
    }
}

struct ProcessorConfiguration: Equatable {
    var kind: ProcessorKind
    var model: String
    var resolvedModel: String { kind.modelID(model) }
    var thinking: String { "off" }
}

enum CLIDiscovery {
    static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ([home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] +
                (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")).joined(separator: ":")
    }
    static func executable(_ command: String) -> URL? {
        for directory in searchPath.components(separatedBy: ":") where directory.hasPrefix("/") {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
    static var environment: [String: String] {
        var result = ["PATH": searchPath, "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                      "LANG": "en_US.UTF-8", "TERM": "dumb", "NO_COLOR": "1", "PI_OFFLINE": "1", "PI_TELEMETRY": "0"]
        for key in ["USER", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR"] { result[key] = ProcessInfo.processInfo.environment[key] }
        return result
    }
}

// Only the resolved credential enters this disposable Pi configuration. The normal
// auth command refreshes the original store with Pi's own locking; no auth symlinks.
final class PiRequest {
    let directory: URL
    var environment: [String: String] {
        var result = CLIDiscovery.environment
        result["PI_CODING_AGENT_DIR"] = directory.path
        return result
    }
    init(provider: String, credential: String, oauth: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rewrite-request-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            // The parent auth command refreshes OAuth before this short-lived snapshot.
            // Never copy the refresh token or let this disposable store rotate it.
            let snapshot: [String: Any] = oauth
                ? ["type": "oauth", "access": credential, "refresh": "", "expires": (Date().timeIntervalSince1970 + 600) * 1000]
                : ["type": "api_key", "key": credential]
            let auth = try JSONSerialization.data(withJSONObject: [provider: snapshot])
            try auth.write(to: directory.appendingPathComponent("auth.json"))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("auth.json").path)
            try Data("{\"compaction\":{\"enabled\":false},\"retry\":{\"enabled\":false}}".utf8).write(to: directory.appendingPathComponent("settings.json"))
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    // Pi's off option omits reasoning from OpenAI requests. Set none explicitly
    // so the server cannot substitute its own reasoning default.
    static let priorityExtension = """
    export default function(pi) {
      pi.on("before_provider_request", event => ({
        ...event.payload,
        service_tier: "priority",
        reasoning: { effort: "none" }
      }));
    }
    """
    @MainActor func rewriteArguments(_ configuration: ProcessorConfiguration) throws -> [String] {
        var arguments = try ProcessorService.arguments(configuration)
        if configuration.kind == .openai {
            let path = directory.appendingPathComponent("rewrite-priority.mjs")
            try Self.priorityExtension.write(to: path, atomically: true, encoding: .utf8)
            arguments += ["--extension", path.path]
        }
        return arguments
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
final class ProcessorService {
    private var runner: ProcessRunner?
    private var checkedExecutable: URL?
    private let executableOverride: URL?
    init(executable: URL? = nil) { executableOverride = executable }
    private var rpc: PiRPC?
    private var rpcRequest: PiRequest?
    private var rpcConfiguration: ProcessorConfiguration?
    private var rpcStarted = Date.distantPast
    private var isRewriting = false
    var processIdentifier: Int32? { rpc?.isRunning == true ? rpc?.processIdentifier : nil }
    func cancel() {
        runner?.cancel()
        if isRewriting { shutdown() }
    }
    func shutdown() {
        rpc?.stop(); rpc = nil; rpcRequest = nil; rpcConfiguration = nil
    }

    static let isolationArguments = ["--offline", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
                                     "--no-prompt-templates", "--no-context-files", "--no-themes", "--no-approve"]
    private func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL,
                     input: String = "", timeout: Double = 90) async throws -> ProcessOutput {
        let runner = ProcessRunner(); self.runner = runner
        defer { if self.runner === runner { self.runner = nil } }
        return try await runner.run(executable: executable, arguments: arguments, environment: environment,
                                    directory: directory, input: input, timeout: timeout)
    }
    private func executable() async throws -> URL {
        guard let executable = executableOverride ?? CLIDiscovery.executable("pi") else {
            throw RewriteError.message("Install Pi, run pi in Terminal and use /login, then click Refresh.")
        }
        if checkedExecutable != executable {
            let request = try PiRequest(provider: "openai-codex", credential: "")
            defer { withExtendedLifetime(request) {} }
            let result = try await run(executable, Self.isolationArguments + ["--help"], environment: request.environment, directory: request.directory, timeout: 10)
            let help = String(decoding: result.stdout, as: UTF8.self)
            guard result.status == 0, (Self.isolationArguments + ["--system-prompt", "--mode", "--thinking", "--extension"]).allSatisfy({ help.contains($0) }) else {
                throw RewriteError.message("Update Pi: this version lacks the isolation options Rewrite requires.")
            }
            checkedExecutable = executable
        }
        return executable
    }
    private func request(_ executable: URL, kind: ProcessorKind) async throws -> PiRequest {
        var environment = CLIDiscovery.environment
        environment["PI_CODING_AGENT_DIR"] = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        // This dedicated Pi command does not load extensions, prompts, or custom model endpoints.
        // Credentials stay in memory and the private request directory, never logs or argv.
        let auth = try await run(executable, ["auth", "check", "--provider", kind.providerID, "--json", "--credentials"],
                                 environment: environment, directory: URL(fileURLWithPath: "/private/tmp"), timeout: 20)
        guard auth.status == 0, let json = try? JSONSerialization.jsonObject(with: auth.stdout) as? [String: Any],
              json["status"] as? String == "ready", let credential = json["credentials"] as? String,
              !credential.isEmpty, !credential.hasPrefix("!"), !credential.contains("\n") else {
            throw RewriteError.message("Sign in to \(kind.rawValue) in Pi: open pi in Terminal, use /login, then Refresh. Codex and Claude CLI sign-ins are not used.")
        }
        try Task.checkCancellation()
        return try PiRequest(provider: kind.providerID, credential: credential, oauth: json["authType"] as? String == "oauth")
    }
    func models(for kind: ProcessorKind) async throws -> [String] {
        let executable = try await executable(), request = try await request(executable, kind: kind)
        defer { withExtendedLifetime(request) {} }
        let result = try await run(executable, Self.isolationArguments + ["--list-models"], environment: request.environment, directory: request.directory, timeout: 20)
        guard result.status == 0 else { throw RewriteError.message("Pi could not list models. Update Pi and check your sign-in, then Refresh.") }
        let models = Self.parseModels(result.stdout, kind: kind)
        guard !models.isEmpty else { throw RewriteError.message("Pi has no models for \(kind.rawValue). Update Pi and check your sign-in, then Refresh.") }
        return models
    }
    static func parseModels(_ data: Data, kind: ProcessorKind) -> [String] {
        let models = String(decoding: data, as: UTF8.self).components(separatedBy: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 6, fields[0] == kind.providerID else { return nil }
            return String(fields[1])
        }
        return Array(Set(models)).sorted { a, b in
            if a == kind.preferredModel { return true }; if b == kind.preferredModel { return false }; return a < b
        }
    }
    static func arguments(_ configuration: ProcessorConfiguration) throws -> [String] {
        let model = configuration.resolvedModel
        guard !model.isEmpty, model.count < 160,
              model.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else {
            throw RewriteError.message("Enter a model ID for the selected provider, without a provider prefix or reasoning suffix.")
        }
        return isolationArguments + ["--mode", "rpc", "--provider", configuration.kind.providerID,
            "--model", model, "--thinking", configuration.thinking, "--system-prompt", Editing.rules]
    }
    // Called serially by the app's warmup task and rewrite task. Never sends a prompt.
    func warmUp(_ configuration: ProcessorConfiguration) async throws {
        do {
            try await prepare(configuration)
            try await rpc?.resetSession()
            try Task.checkCancellation()
        } catch { shutdown(); throw error }
    }
    private func prepare(_ configuration: ProcessorConfiguration) async throws {
        _ = try Self.arguments(configuration)
        // Refresh the short-lived auth snapshot well before its token can expire.
        // Healthy requests with the same configuration reuse one process.
        if rpc?.isRunning != true || rpcConfiguration != configuration || Date().timeIntervalSince(rpcStarted) > 180 {
            shutdown()
            let executable = try await executable(), request = try await request(executable, kind: configuration.kind)
            try Task.checkCancellation()
            rpc = try PiRPC(executable: executable, arguments: request.rewriteArguments(configuration),
                            environment: request.environment, directory: request.directory)
            rpcRequest = request; rpcConfiguration = configuration; rpcStarted = Date()
        }
    }
    func rewrite(_ source: String, action: EditAction, configuration: ProcessorConfiguration) async throws -> String {
        guard !isRewriting else { throw RewriteError.message("A rewrite is already finishing. Try again in a moment.") }
        isRewriting = true
        defer { isRewriting = false }
        do {
            try await prepare(configuration)
            guard let rpc else { throw RewriteError.message("Pi could not start. Try again.") }
            try await rpc.resetSession()
            let output = try await rpc.send("prompt", message: Editing.payload(source, action: action))
            let result = try Self.parse(output)
            // Clear text immediately after completion, not only before the next request.
            try await rpc.resetSession()
            try Task.checkCancellation()
            return result
        } catch {
            shutdown()
            throw error
        }
    }
    static func parse(_ data: Data) throws -> String {
        let failure = RewriteError.message("Pi did not return a completed rewrite. Check your sign-in and model, then retry.")
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
        return try Editing.validate(result)
    }
}
