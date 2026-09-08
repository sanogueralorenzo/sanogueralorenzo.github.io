import Foundation

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
final class PiEnvironment {
    static let isolationArguments = ["--offline", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
                                     "--no-prompt-templates", "--no-context-files", "--no-themes", "--no-approve"]
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
    @MainActor func rewriteArguments(_ provider: RewriteProvider) throws -> [String] {
        var arguments = Self.isolationArguments + ["--mode", "rpc", "--provider", provider.providerID,
            "--model", provider.preferredModel, "--thinking", "off", "--system-prompt", Editing.rules]
        if provider == .openai {
            let path = directory.appendingPathComponent("rewrite-priority.mjs")
            try Self.priorityExtension.write(to: path, atomically: true, encoding: .utf8)
            arguments += ["--extension", path.path]
        }
        return arguments
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

