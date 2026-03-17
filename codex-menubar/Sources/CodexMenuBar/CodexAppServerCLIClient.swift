import Foundation

final class CodexAppServerCLIClient: @unchecked Sendable {
    enum AutoRemoveMode: String {
        case archive
        case delete
    }

    enum Status: Equatable {
        case notInstalled
        case ready
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

        return .ready
    }

    func runAutoRemove(olderThanDays: Int, mode: AutoRemoveMode) throws {
        guard olderThanDays > 0 else {
            throw Error(message: "olderThanDays must be greater than zero.")
        }

        _ = try run([
            "auto-remove",
            "--older-than-days", String(olderThanDays),
            "--mode", mode.rawValue
        ])
    }

    func isTitleWatcherRunning() throws -> Bool {
        let output = try run(["watch", "thread-titles", "status"])
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("running")
    }

    func startTitleWatcher() throws {
        _ = try run(["watch", "thread-titles", "start"])
    }

    func stopTitleWatcher() throws {
        _ = try run(["watch", "thread-titles", "stop"])
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let executablePath else {
            throw Error(message: CLIExecutableResolver.unresolvedMessage(commandName: "codex-app-server"))
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw Error(message: "codex-app-server CLI not found at \(executablePath). Run codex-app-server/scripts/install.sh first.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["sessions"] + arguments
        process.environment = CLIProcessEnvironment.make()

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
            throw Error(message: "codex-app-server sessions command failed: codex-app-server sessions \(arguments.joined(separator: " "))")
        }

        return stdoutText
    }

    private static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(commandName: "codex-app-server")
    }
}
