import Foundation

struct CodexRateLimitsSnapshot {
    let entries: [String]
    let isMock: Bool
    let sourceNote: String
}

final class CodexRateLimitsProvider: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> CodexRateLimitsSnapshot {
        guard let codexExecutablePath = resolveCodexExecutablePath() else {
            return mockSnapshot(reason: "Codex CLI not found")
        }

        guard cliMentionsLimitsCommand(codexExecutablePath: codexExecutablePath) else {
            return mockSnapshot(reason: "Rate limits command unavailable")
        }

        if let output = try? run(executablePath: codexExecutablePath, arguments: ["limits", "--plain"]),
           !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !lines.isEmpty {
                return CodexRateLimitsSnapshot(entries: lines,
                                               isMock: false,
                                               sourceNote: "From Codex CLI")
            }
        }

        return mockSnapshot(reason: "Could not fetch from Codex CLI")
    }

    private func mockSnapshot(reason: String) -> CodexRateLimitsSnapshot {
        // MOCK DATA ONLY
        // Replace with real limits once Codex CLI exposes a stable limits endpoint.
        return CodexRateLimitsSnapshot(
            entries: [
                "Requests: 46 / 100 (hour)",
                "Input tokens: 1.3M / 5.0M (day)",
                "Output tokens: 280k / 2.0M (day)",
                "Resets in: 21m"
            ],
            isMock: true,
            sourceNote: "Mock (\(reason))"
        )
    }

    private func cliMentionsLimitsCommand(codexExecutablePath: String) -> Bool {
        guard let helpOutput = try? run(executablePath: codexExecutablePath, arguments: ["--help"]) else {
            return false
        }
        let lower = helpOutput.lowercased()
        return lower.contains("\n  limits") || lower.contains("\nlimits")
    }

    private func resolveCodexExecutablePath() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["CODEX_BIN"], fileManager.isExecutableFile(atPath: custom) {
            return custom
        }

        guard let npmGlobalCodexPath = CLIExecutableResolver.resolve(commandName: "codex") else {
            return nil
        }
        if fileManager.isExecutableFile(atPath: npmGlobalCodexPath) {
            return npmGlobalCodexPath
        }

        return nil
    }

    private func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)

        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return stdoutText
        }

        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(domain: "CodexRateLimitsProvider",
                      code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: stderrText])
    }
}
