import Foundation

struct PullRequestReference: Sendable {
  let owner: String
  let repo: String
  let number: Int

  var repoFullName: String { "\(owner)/\(repo)" }

  static func parse(urlString: String) -> PullRequestReference? {
    guard
      let components = URLComponents(string: urlString),
      components.host?.lowercased() == "github.com"
    else {
      return nil
    }
    let parts = components.path.split(separator: "/").map(String.init)
    guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]) else {
      return nil
    }
    return PullRequestReference(owner: parts[0], repo: parts[1], number: number)
  }
}

struct PullRequestDetails: Sendable {
  let reference: PullRequestReference
  let title: String
  let url: String
  let baseRefName: String
  let headRefName: String
}

final class CodexActionRunner: @unchecked Sendable {
  private let fileManager: FileManager
  private let paths: AppPaths
  private let github: GitHubCLIClient
  private let jsonDecoder = JSONDecoder()

  init(paths: AppPaths = AppPaths(), github: GitHubCLIClient, fileManager: FileManager = .default) {
    self.paths = paths
    self.github = github
    self.fileManager = fileManager
  }

  func integrationStatus() async -> IntegrationStatus {
    guard Shell.resolve("codex") != nil else {
      return IntegrationStatus(
        toolName: "codex",
        state: .missing(summary: "codex missing", detail: "Install Codex CLI and authenticate.")
      )
    }

    do {
      let result = try await Shell.run(
        executable: "codex",
        arguments: ["login", "status"],
        timeout: 15
      )
      let line = result.stdout.split(separator: "\n").first.map(String.init) ?? "Authenticated"
      return IntegrationStatus(toolName: "codex", state: .ready(summary: "Authenticated", detail: line))
    } catch {
      return IntegrationStatus(
        toolName: "codex",
        state: .actionNeeded(summary: "Auth required", detail: error.localizedDescription)
      )
    }
  }

  func runApplyFeedback(for pullRequest: PullRequestSummary) async throws -> String {
    let details = try await fetchDetails(for: pullRequest)
    let feedback = try await github.fetchPullRequestFeedback(
      owner: details.reference.owner,
      repo: details.reference.repo,
      number: details.reference.number
    )

    guard !feedback.lines.isEmpty else {
      return "No PR feedback found."
    }

    try paths.ensureExists(fileManager: fileManager)
    let cacheRepo = try await ensureRepoCache(for: details.reference)
    let worktree = paths.worktreesRoot
      .appendingPathComponent("feedback", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
      at: worktree.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let localBranch = "pr-reviews-\(details.reference.number)"

    do {
      _ = try await Shell.run(
        executable: "git",
        arguments: [
          "fetch", "origin",
          "refs/heads/\(details.headRefName):refs/remotes/origin/\(details.headRefName)",
        ],
        currentDirectory: cacheRepo,
        timeout: 60
      )
      _ = try await Shell.run(
        executable: "git",
        arguments: [
          "worktree", "add",
          "-B", localBranch,
          worktree.path,
          "refs/remotes/origin/\(details.headRefName)",
        ],
        currentDirectory: cacheRepo,
        timeout: 60
      )

      let outputFile = worktree.appendingPathComponent("apply-feedback-output.txt")
      let prompt = applyFeedbackPrompt(details: details, feedback: feedback)
      _ = try await Shell.run(
        executable: "codex",
        arguments: ["exec", "--full-auto", "--output-last-message", outputFile.path, "-"],
        currentDirectory: worktree,
        standardInput: prompt,
        timeout: 3600
      )

      let output = (try String(contentsOf: outputFile)).trimmingCharacters(in: .whitespacesAndNewlines)
      try? await removeWorktree(worktree, from: cacheRepo)
      return output.isEmpty ? "Apply feedback completed." : output
    } catch {
      try? await removeWorktree(worktree, from: cacheRepo)
      throw error
    }
  }

  private func fetchDetails(for pullRequest: PullRequestSummary) async throws -> PullRequestDetails {
    struct ViewResponse: Decodable {
      let title: String
      let url: String
      let baseRefName: String
      let headRefName: String
    }

    guard let reference = PullRequestReference.parse(urlString: pullRequest.url) else {
      throw ShellError.nonZeroExit(command: pullRequest.url, message: "Invalid PR URL")
    }

    let result = try await Shell.run(
      executable: "gh",
      arguments: [
        "pr", "view", String(reference.number),
        "--repo", reference.repoFullName,
        "--json", "title,url,baseRefName,headRefName",
      ],
      timeout: 30
    )
    let view = try jsonDecoder.decode(ViewResponse.self, from: Data(result.stdout.utf8))
    return PullRequestDetails(
      reference: reference,
      title: view.title,
      url: view.url,
      baseRefName: view.baseRefName,
      headRefName: view.headRefName
    )
  }

  private func ensureRepoCache(for reference: PullRequestReference) async throws -> URL {
    let ownerDir = paths.reposRoot.appendingPathComponent(reference.owner, isDirectory: true)
    let repoDir = ownerDir.appendingPathComponent(reference.repo, isDirectory: true)
    try fileManager.createDirectory(at: ownerDir, withIntermediateDirectories: true)

    if !fileManager.fileExists(atPath: repoDir.path) {
      _ = try await Shell.run(
        executable: "gh",
        arguments: ["repo", "clone", reference.repoFullName, repoDir.path],
        timeout: 600
      )
    }

    _ = try await Shell.run(
      executable: "git",
      arguments: ["fetch", "origin", "--prune"],
      currentDirectory: repoDir,
      timeout: 120
    )
    return repoDir
  }

  private func removeWorktree(_ worktree: URL, from cacheRepo: URL) async throws {
    _ = try await Shell.run(
      executable: "git",
      arguments: ["worktree", "remove", "--force", worktree.path],
      currentDirectory: cacheRepo,
      timeout: 60
    )
    if fileManager.fileExists(atPath: worktree.path) {
      try? fileManager.removeItem(at: worktree)
    }
  }
  private func applyFeedbackPrompt(details: PullRequestDetails, feedback: PullRequestFeedback) -> String {
    let feedbackLines = feedback.lines.prefix(80).map { "- \($0)" }.joined(separator: "\n")
    return """
    You are addressing feedback on GitHub PR \(details.url).
    The current repository is checked out on a disposable local branch based on the PR head branch `\(details.headRefName)`.
    Review the feedback below, implement the actionable changes that are still relevant, run targeted validation, and push the updates back to `origin HEAD:\(details.headRefName)`.
    Do not create a new branch or a new pull request.
    Format file names, classes, methods, and variables as inline code.
    In the final response, summarize what you changed and any feedback you intentionally did not apply.

    Existing PR feedback:
    \(feedbackLines)
    """
  }
}
