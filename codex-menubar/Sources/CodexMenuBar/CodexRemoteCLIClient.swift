import Foundation

final class CodexRemoteCLIClient: @unchecked Sendable {
    enum Status: Equatable {
        case notInstalled
        case stopped
        case running(pid: Int32?)
    }

    enum MenuAction {
        case install
        case start
        case stop
    }

    enum InstallAction {
        case openGuide(URL)
        case runInstall
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
        guard installedExecutablePath() != nil else {
            return .notInstalled
        }

        let output = try run(["status", "--plain"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if output == "stopped" {
            return .stopped
        }
        if output.hasPrefix("running:") {
            let pidPart = output.replacingOccurrences(of: "running:", with: "")
            return .running(pid: Int32(pidPart))
        }
        throw Error(message: "Unexpected codex-remote status output: \(output)")
    }

    func menuAction(remoteStatus: Status?, isLoading: Bool) -> MenuAction {
        if isLoading {
            return .start
        }

        guard let remoteStatus else {
            return .start
        }

        switch remoteStatus {
        case .notInstalled:
            return .install
        case .stopped:
            return .start
        case .running:
            return .stop
        }
    }

    func isRunning() throws -> Bool {
        if case .running = try status() {
            return true
        }
        return false
    }

    func installAction() throws -> InstallAction {
        switch try status() {
        case .notInstalled:
            return .openGuide(installGuideURL())
        case .stopped, .running:
            return .runInstall
        }
    }

    func install() throws {
        guard installedExecutablePath() != nil else {
            throw Error(message: "Codex Remote CLI is not installed.")
        }
        _ = try run(["install"])
    }

    func start() throws {
        guard installedExecutablePath() != nil else {
            throw Error(message: "Codex Remote CLI is not installed.")
        }
        _ = try run(["start", "--plain"])
    }

    func stop() throws {
        guard installedExecutablePath() != nil else {
            throw Error(message: "Codex Remote CLI is not installed.")
        }
        _ = try run(["stop", "--plain"])
    }

    func restart() throws {
        guard installedExecutablePath() != nil else {
            throw Error(message: "Codex Remote CLI is not installed.")
        }
        _ = try run(["restart", "--plain"])
    }

    func installGuideURL() -> URL {
        URL(string: "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/tree/main/codex-remote")!
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let executablePath else {
            throw Error(message: CLIExecutableResolver.unresolvedMessage(commandName: "codex-remote"))
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw Error(message: "codex-remote CLI not found at \(executablePath). Run codex-remote/scripts/install.sh first.")
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
            throw Error(message: "codex-remote command failed: codex-remote \(arguments.joined(separator: " "))")
        }

        return stdoutText
    }

    private static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(commandName: "codex-remote")
    }

    private func installedExecutablePath() -> String? {
        guard let executablePath else {
            return nil
        }
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            return nil
        }
        return executablePath
    }
}
