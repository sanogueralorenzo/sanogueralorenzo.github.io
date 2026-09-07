import Foundation

enum ProcessorKind: String, CaseIterable {
    case codex = "Codex CLI", claude = "Claude CLI", ollama = "Ollama (local)"
    var notice: String {
        switch self {
        case .codex: return "Uses your Codex sign-in. Selected text is sent to OpenAI."
        case .claude: return "Uses your Claude sign-in. Selected text is sent to Anthropic."
        case .ollama: return "Runs on this Mac through Ollama at 127.0.0.1:11434. Cloud models are refused."
        }
    }
    var command: String { self == .codex ? "codex" : "claude" }
}

struct ProcessorConfiguration {
    var kind: ProcessorKind
    var model: String
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
        // The desktop app may include Codex even when no shell installation exists.
        if command == "codex" {
            let bundled = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        return nil
    }
    static var environment: [String: String] {
        // Do not inherit project variables, debugging, custom endpoint overrides, or hooks.
        var result = ["PATH": searchPath, "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                      "LANG": "en_US.UTF-8", "TERM": "dumb", "NO_COLOR": "1"]
        for key in ["USER", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR"] {
            result[key] = ProcessInfo.processInfo.environment[key]
        }
        return result
    }
}

// Reject redirects as well as non-loopback endpoints: local must stay local.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class ProcessorService {
    private var runner: ProcessRunner?
    private let session: URLSession
    private let port: UInt16
    init(port: UInt16 = 11434) {
        self.port = port
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 100
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func cancel() { runner?.cancel() }

    func models(for kind: ProcessorKind) async throws -> [String] {
        if kind == .ollama {
            let data = try await local("tags")
            guard let models = data["models"] as? [[String: Any]] else { throw unavailableLocal() }
            return models.compactMap { model in
                guard model["remote_host"] == nil, model["remote_model"] == nil,
                      let name = model["name"] as? String, !name.lowercased().contains("cloud") else { return nil }
                return name
            }.sorted()
        }
        guard let executable = CLIDiscovery.executable(kind.command) else { throw unavailableCLI(kind) }
        let runner = ProcessRunner(); self.runner = runner
        let result = try await runner.run(executable: executable, arguments: kind == .codex ? ["exec", "--help"] : ["--help"], environment: CLIDiscovery.environment, directory: URL(fileURLWithPath: "/private/tmp"), timeout: 10)
        let help = String(decoding: result.stdout, as: UTF8.self)
        let required = kind == .codex ? ["--ephemeral", "--ignore-user-config", "--ignore-rules", "--sandbox", "--json"] : ["--safe-mode", "--tools", "--no-session-persistence", "--strict-mcp-config", "--setting-sources", "--system-prompt"]
        guard result.status == 0, required.allSatisfy({ help.contains($0) }) else {
            throw RewriteError.message("Update \(kind.rawValue): this version lacks the isolation options Rewrite requires.")
        }
        if kind == .claude { return ["default", "haiku", "sonnet", "opus"] }
        // Read only public model metadata, never project settings or conversation history.
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        if let data = try? Data(contentsOf: cache), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            return ["default"] + models.filter { $0["visibility"] as? String != "hide" }.compactMap { $0["slug"] as? String }.filter { !$0.isEmpty }.sorted()
        }
        return ["default"]
    }

    func rewrite(_ source: String, action: EditAction, configuration: ProcessorConfiguration) async throws -> String {
        let payload = try Editing.payload(source, action: action)
        if configuration.kind == .ollama {
            guard !configuration.model.isEmpty, configuration.model != "default" else { throw unavailableLocal() }
            let info = try await local("show", body: ["model": configuration.model])
            guard Self.isLocalModel(info, name: configuration.model) else {
                throw RewriteError.message("Choose a downloaded local model. Rewrite refuses Ollama cloud models.")
            }
            let declaredContext = (info["model_info"] as? [String: Any])?.first(where: { $0.key.hasSuffix(".context_length") })?.value as? Int ?? 16384
            let context = min(16384, declaredContext)
            guard payload.utf8.count + Editing.rules.utf8.count + 2048 <= context else {
                throw RewriteError.message("This passage is too long for the local model’s context. Select a shorter passage and try again.")
            }
            let response = try await local("chat", body: ["model": configuration.model, "stream": false, "think": false,
                "messages": [["role": "system", "content": Editing.rules], ["role": "user", "content": payload]],
                "options": ["temperature": 0.2, "num_ctx": context]])
            guard response["done_reason"] as? String != "length" else {
                throw RewriteError.message("The local model stopped before finishing. Select a shorter passage and try again.")
            }
            guard response["done"] as? Bool == true, let message = response["message"] as? [String: Any],
                  let content = message["content"] as? String else { throw unavailableLocal() }
            return try Editing.validate(content)
        }
        _ = try await models(for: configuration.kind) // Fail closed if installed flags changed.
        try Task.checkCancellation()
        guard let executable = CLIDiscovery.executable(configuration.kind.command) else { throw unavailableCLI(configuration.kind) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rewrite-request-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var environment = CLIDiscovery.environment
        var arguments: [String]
        var input = payload
        if configuration.kind == .codex {
            let existingHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            // Preserve the authentication store's identity so token refresh and Keychain
            // access work normally. All request state and logs use the temporary directory.
            environment["CODEX_HOME"] = existingHome.path
            environment["RUST_LOG"] = "off"
            let rules = directory.appendingPathComponent("instructions.txt")
            try Editing.rules.write(to: rules, atomically: true, encoding: .utf8)
            arguments = Self.codexArguments(rules: rules)
            arguments += ["-c", "sqlite_home=\"\(directory.path)\"", "-c", "log_dir=\"\(directory.path)\""]
        } else {
            environment["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
            environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
            environment["DISABLE_TELEMETRY"] = "1"
            environment["DISABLE_ERROR_REPORTING"] = "1"
            // Discard debug output, which some Claude versions otherwise write by default.
            arguments = ["--print", "--output-format", "json", "--no-session-persistence", "--safe-mode",
                         "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                         "--setting-sources", "", "--system-prompt", Editing.rules, "--debug-file", "/dev/null"]
        }
        if !configuration.model.isEmpty && configuration.model != "default" { arguments += ["--model", configuration.model] }
        if configuration.kind == .codex { arguments.append("-"); input = payload }
        let runner = ProcessRunner(); self.runner = runner
        let output = try await runner.run(executable: executable, arguments: arguments, environment: environment, directory: work, input: input)
        guard output.status == 0 else {
            if configuration.kind == .claude,
               let envelope = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
               let message = envelope["result"] as? String,
               ["not logged in", "authenticate", "token has expired"].contains(where: { message.lowercased().contains($0) }) {
                throw RewriteError.message("Claude’s sign-in is missing or expired. Open claude in Terminal and run /login, then try again.")
            }
            throw RewriteError.message("\(configuration.kind.rawValue) failed. Check your sign-in, connection, usage limit, and model in Terminal, then retry. Your original text is unchanged.")
        }
        return try Self.parse(output.stdout, kind: configuration.kind)
    }

    static func codexArguments(rules: URL) -> [String] {
        var args = ["exec", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--sandbox", "read-only", "--json", "--color", "never"]
        for setting in ["approval_policy=\"never\"", "project_doc_max_bytes=0", "web_search=\"disabled\"",
                        "history.persistence=\"none\"", "analytics.enabled=false", "feedback.enabled=false",
                        "model_instructions_file=\"\(rules.path)\""] { args += ["-c", setting] }
        for feature in ["shell_tool", "unified_exec", "shell_snapshot", "apps", "plugins", "hooks", "memories", "multi_agent",
                        "multi_agent_v2", "browser_use", "computer_use", "image_generation", "view_image", "code_mode", "code_mode_host",
                        "skill_search", "workspace_dependencies", "tool_suggest"] { args += ["--disable", feature] }
        args += ["--enable", "skip_host_skill_discovery"]
        return args
    }

    static func parse(_ data: Data, kind: ProcessorKind) throws -> String {
        if kind == .claude {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["is_error"] as? Bool != true,
                  let result = json["result"] as? String else { throw RewriteError.message("Claude did not return a completed edit. Check your sign-in and model in Settings.") }
            return try Editing.validate(result)
        }
        var result: String?, completed = false
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if json["type"] as? String == "turn.completed" { completed = true }
            if json["type"] as? String == "item.completed", let item = json["item"] as? [String: Any] {
                if item["type"] as? String == "agent_message" { result = item["text"] as? String }
                if ["command_execution", "mcp_tool_call", "file_change", "web_search"].contains(item["type"] as? String ?? "") {
                    throw RewriteError.message("The processor attempted a tool action. The edit was discarded; update the CLI before retrying.")
                }
            }
        }
        guard completed, let result else { throw RewriteError.message("Codex did not return a completed edit. Check your sign-in and model in Settings.") }
        return try Editing.validate(result)
    }

    static func isLocalModel(_ info: [String: Any], name: String) -> Bool {
        guard !name.lowercased().contains("cloud"), info["remote_host"] == nil, info["remote_model"] == nil,
              let details = info["details"] as? [String: Any], let size = details["parameter_size"] as? String, !size.isEmpty,
              let capabilities = info["capabilities"] as? [String], capabilities.contains("completion") else { return false }
        return true
    }
    private func local(_ endpoint: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/" + endpoint)!)
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw unavailableLocal() }
            return json
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .timedOut {
            throw RewriteError.message("The local model timed out. Try a shorter passage or a smaller model.")
        }
        catch { if Task.isCancelled { throw CancellationError() }; throw unavailableLocal() }
    }
    private func unavailableCLI(_ kind: ProcessorKind) -> RewriteError { .message("Install \(kind.rawValue), sign in with \(kind.command) in Terminal, then click Refresh. Rewrite checks ~/.local/bin, Homebrew, and PATH.") }
    private func unavailableLocal() -> RewriteError { .message("Start Ollama on this Mac and download a text model with ollama pull <model>. Then choose the model in Settings. Only 127.0.0.1:11434 is supported.") }
}
