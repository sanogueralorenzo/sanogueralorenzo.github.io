import Foundation

final class CodexSessionsCLIClient: @unchecked Sendable {
    enum Status: Equatable {
        case notInstalled
        case ready(activeSessionCount: Int)
    }

    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let executablePath: String?
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.executablePath = Self.resolveExecutablePath()
    }

    func status() throws -> Status {
        guard let executablePath else {
            return .notInstalled
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            return .notInstalled
        }

        let output = try run(["list", "--plain"])
        let activeSessionCount = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("next_cursor\t")
            }
            .count

        return .ready(activeSessionCount: activeSessionCount)
    }

    func removeStaleSessions(olderThanDays: Int) throws {
        guard olderThanDays > 0 else {
            throw Error(message: "olderThanDays must be greater than zero.")
        }

        _ = try run([
            "prune",
            "--older-than-days", String(olderThanDays),
            "--hard"
        ])
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let executablePath else {
            throw Error(message: CLIExecutableResolver.unresolvedMessage(commandName: "codex-sessions"))
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw Error(message: "codex-sessions CLI not found at \(executablePath). Run codex-sessions/scripts/install.sh first.")
        }

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
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                throw Error(message: message)
            }
            throw Error(message: "codex-sessions command failed: codex-sessions \(arguments.joined(separator: " "))")
        }

        return stdoutText
    }

    private static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(commandName: "codex-sessions")
    }
}
