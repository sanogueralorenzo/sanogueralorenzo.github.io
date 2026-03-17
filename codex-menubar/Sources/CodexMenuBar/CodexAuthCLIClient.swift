import Foundation

final class CodexAuthCLIClient: @unchecked Sendable {
    enum MenuProfileAction {
        case use
        case remove
    }

    struct MenuProfile {
        let normalizedName: String
        let isCurrent: Bool
        let actions: [MenuProfileAction]
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

    func listProfiles() throws -> [String] {
        let output = try run(["list", "--plain"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func currentProfileName() throws -> String? {
        let value = try run(["current", "--plain"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "(untracked)" {
            return nil
        }
        return value
    }

    func saveProfile(name: String) throws {
        _ = try run(["save", name])
    }

    func useProfile(name: String) throws {
        _ = try run(["use", name])
    }

    func removeProfile(name: String) throws {
        _ = try run(["remove", name])
    }

    func startWatcher() throws {
        _ = try run(["watch", "start"])
    }

    func stopWatcher() throws {
        _ = try run(["watch", "stop"])
    }

    func menuProfiles(currentProfileName: String?,
                      profiles: [String],
                      isLoading: Bool) -> [MenuProfile] {
        guard !isLoading else {
            return []
        }

        return profiles.map { normalizedName in
            let isCurrent = normalizedName == currentProfileName
            let actions: [MenuProfileAction] = isCurrent ? [.remove] : [.use, .remove]
            return MenuProfile(normalizedName: normalizedName,
                               isCurrent: isCurrent,
                               actions: actions)
        }
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let executablePath else {
            throw Error(message: CLIExecutableResolver.unresolvedMessage(commandName: "codex-auth"))
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw Error(message: "codex-auth CLI not found at \(executablePath). Run codex-auth/scripts/install.sh first.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
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
            throw Error(message: "codex-auth command failed: codex-auth \(arguments.joined(separator: " "))")
        }

        return stdoutText
    }

    private static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(commandName: "codex-auth")
    }
}
