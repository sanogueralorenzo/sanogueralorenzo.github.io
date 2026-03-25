import Foundation

final class CodexCoreCLIClient: @unchecked Sendable {
    struct AgentsConfig: Decodable, Sendable {
        let stateVersion: Int
        let initializedAt: String
        let allowedRepos: [String]
    }

    struct AvailableRepo: Decodable, Sendable {
        let fullName: String
    }

    struct ReviewPullRequest: Decodable {
        let owner: String
        let repo: String
        let number: Int
        let title: String
        let url: String
        let createdAt: String

        var repositoryFullName: String {
            "\(owner)/\(repo)"
        }

        var repositoryURL: String {
            "https://github.com/\(owner)/\(repo)"
        }

        var shortMenuTitle: String {
            "#\(number) \(title)"
        }
    }

    struct ReviewRunResult: Decodable {
        struct FailedCommentDetail: Decodable {
            let title: String
            let path: String?
            let startLine: Int
            let endLine: Int
            let reason: String
        }

        let reviewId: String
        let owner: String
        let repo: String
        let number: Int
        let url: String
        let postedComments: Int
        let failedComments: Int
        let failedCommentDetails: [FailedCommentDetail]
        let summary: String
    }

    struct ReviewJob: Decodable {
        enum MenuState: String, Decodable {
            case published = "published"
            case needsAttention = "needs_attention"
            case inProgress = "in_progress"
        }

        let id: String
        let owner: String
        let repo: String
        let number: Int
        let url: String?
        let status: String
        let currentStep: String
        let createdAt: String
        let postedComments: Int
        let failedComments: Int
        let summary: String?
        let menuState: MenuState

        var repositoryFullName: String {
            "\(owner)/\(repo)"
        }

        var displayTitle: String {
            "#\(number) \(repo)"
        }
    }

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
        guard olderThanDays >= 0 else {
            throw Error(message: "olderThanDays must be zero or greater.")
        }

        _ = try runSessions([
            "prune",
            "--older-than-days", String(olderThanDays),
            "--mode", mode.rawValue
        ])
    }

    func isTitleWatcherRunning() throws -> Bool {
        let output = try runSessions(["watch", "thread-titles", "status"])
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("running")
    }

    func startTitleWatcher() throws {
        _ = try runSessions(["watch", "thread-titles", "start"])
    }

    func stopTitleWatcher() throws {
        _ = try runSessions(["watch", "thread-titles", "stop"])
    }

    func listReviewPullRequests() throws -> [ReviewPullRequest] {
        let output = try runAgents(["review", "list", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ReviewPullRequest].self, from: Data(output.utf8))
    }

    func runReview(pullRequest: String) throws -> ReviewRunResult {
        let output = try runAgents(["review", "run", pullRequest, "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReviewRunResult.self, from: Data(output.utf8))
    }

    func listReviewJobs() throws -> [ReviewJob] {
        let output = try runAgents(["review", "jobs", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ReviewJob].self, from: Data(output.utf8))
    }

    func agentsConfig() throws -> AgentsConfig {
        let output = try runAgents(["config", "show", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AgentsConfig.self, from: Data(output.utf8))
    }

    func availableRepos() throws -> [AvailableRepo] {
        let output = try runAgents(["config", "available-repos", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([AvailableRepo].self, from: Data(output.utf8))
    }

    func setAllowedRepos(_ repos: [String]) throws {
        if repos.isEmpty {
            _ = try runAgents(["config", "clear-allowed-repos"])
            return
        }
        _ = try runAgents(["config", "set-allowed-repos"] + repos)
    }

    private func runSessions(_ arguments: [String]) throws -> String {
        try run(commandGroup: "sessions", arguments: arguments)
    }

    private func runAgents(_ arguments: [String]) throws -> String {
        try run(commandGroup: "agents", arguments: arguments)
    }

    private func run(commandGroup: String, arguments: [String]) throws -> String {
        guard let executablePath else {
            throw Error(message: CLIExecutableResolver.unresolvedMessage(commandName: "codex-core"))
        }

        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw Error(message: "codex-core CLI not found at \(executablePath). Run codex/codex-core/scripts/install.sh first.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [commandGroup] + arguments
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
            throw Error(message: "codex-core \(commandGroup) command failed: codex-core \(commandGroup) \(arguments.joined(separator: " "))")
        }

        return stdoutText
    }

    private static func resolveExecutablePath() -> String? {
        CLIExecutableResolver.resolve(commandName: "codex-core")
    }
}
