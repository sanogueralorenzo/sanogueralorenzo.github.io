import Foundation

final class CodexSessionsCLIClient: @unchecked Sendable {
    enum Status: Equatable {
        case notInstalled
        case ready(activeSessionCount: Int)
    }

    struct SessionOption: Equatable {
        let id: String
        let title: String
        let folder: String
        let lastUpdatedAt: String
    }

    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ListResponse: Decodable {
        let data: [ListEntry]
    }

    private struct ListEntry: Decodable {
        let id: String
        let title: String?
        let folder: String
        let archived: Bool
        let last_updated_at: String
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

        let activeSessionCount = try listActiveSessions().count

        return .ready(activeSessionCount: activeSessionCount)
    }

    func listActiveSessions() throws -> [SessionOption] {
        let output = try run(["list", "--all", "--json", "--sort-by", "updated_at"])
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return response.data
            .filter { !$0.archived }
            .map { entry in
                let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedTitle = (title?.isEmpty == false) ? title! : "(no title)"
                return SessionOption(id: entry.id,
                                     title: cleanedTitle,
                                     folder: folderLabel(from: entry.folder),
                                     lastUpdatedAt: entry.last_updated_at)
            }
    }

    func listStaleSessions(olderThanDays: Int) throws -> [SessionOption] {
        guard olderThanDays > 0 else {
            throw Error(message: "olderThanDays must be greater than zero.")
        }

        let output = try run([
            "list",
            "--all",
            "--json",
            "--sort-by", "updated_at",
            "--older-than-days", String(olderThanDays)
        ])
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        return response.data
            .filter { !$0.archived }
            .map { entry in
                let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedTitle = (title?.isEmpty == false) ? title! : "(no title)"
                return SessionOption(id: entry.id,
                                     title: cleanedTitle,
                                     folder: folderLabel(from: entry.folder),
                                     lastUpdatedAt: entry.last_updated_at)
            }
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

    func deleteSessions(ids: [String]) throws {
        let normalizedIDs = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedIDs.isEmpty else {
            return
        }

        var arguments = ["delete", "--plain"]
        arguments.append(contentsOf: normalizedIDs)
        _ = try run(arguments)
    }

    func mergeSessions(targetID: String, mergeID: String) throws {
        guard !targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error(message: "Target thread cannot be empty.")
        }
        guard !mergeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error(message: "Merger thread cannot be empty.")
        }
        guard targetID != mergeID else {
            throw Error(message: "Target and merger threads must be different.")
        }

        _ = try run([
            "merge",
            "--target", targetID,
            "--merge", mergeID
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

    private func folderLabel(from folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "unknown"
        }
        return trimmed
    }
}
