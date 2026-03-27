import Foundation

struct ReviewWorkspace: Sendable {
  let cacheRepoDir: URL
  let repoDir: URL
}

struct FileDiffLines: Sendable {
  var left = Set<Int>()
  var right = Set<Int>()
}

enum DiffSide: String, Sendable {
  case left = "LEFT"
  case right = "RIGHT"
}

func checkoutPullRequest(
  paths: AppPaths,
  reference: PullRequestReference,
  pullRequest: ReviewPullRequestView,
  fileManager: FileManager = .default
) async throws -> ReviewWorkspace {
  try paths.ensureExists(fileManager: fileManager)
  let cacheRepoDir = paths.reposRoot
    .appendingPathComponent(reference.owner, isDirectory: true)
    .appendingPathComponent(reference.repo, isDirectory: true)
  let worktreeDir = paths.worktreesRoot
    .appendingPathComponent("review", isDirectory: true)
    .appendingPathComponent(reference.owner, isDirectory: true)
    .appendingPathComponent(reference.repo, isDirectory: true)
    .appendingPathComponent("pr-\(reference.number)-\(UUID().uuidString)", isDirectory: true)

  try fileManager.createDirectory(
    at: cacheRepoDir.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try fileManager.createDirectory(
    at: worktreeDir.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  if fileManager.fileExists(atPath: cacheRepoDir.path) {
    try await runGit(repoDir: cacheRepoDir, args: ["fetch", "--all", "--prune"])
  } else {
    _ = try await Shell.run(
      executable: "gh",
      arguments: ["repo", "clone", reference.repoFullName, cacheRepoDir.path, "--", "--quiet"],
      timeout: 600
    )
  }

  let remoteRef = "refs/pull/\(reference.number)/head:refs/remotes/origin/pr/\(reference.number)"
  try await runGit(repoDir: cacheRepoDir, args: ["fetch", "--force", "origin", remoteRef])
  try await runGit(
    repoDir: cacheRepoDir,
    args: ["worktree", "add", "--force", "--detach", worktreeDir.path, "refs/remotes/origin/pr/\(reference.number)"]
  )
  try await runGit(repoDir: worktreeDir, args: ["rev-parse", "--verify", "origin/\(pullRequest.baseRefName)"])

  return ReviewWorkspace(cacheRepoDir: cacheRepoDir, repoDir: worktreeDir)
}

func removeReviewWorktree(_ workspace: ReviewWorkspace, fileManager: FileManager = .default) async {
  _ = try? await runGit(repoDir: workspace.cacheRepoDir, args: ["worktree", "remove", "--force", workspace.repoDir.path])
  _ = try? await runGit(repoDir: workspace.cacheRepoDir, args: ["worktree", "prune"])
  if fileManager.fileExists(atPath: workspace.repoDir.path) {
    try? fileManager.removeItem(at: workspace.repoDir)
  }
}

func resolveMergeBase(repoDir: URL, baseRefName: String) async throws -> String? {
  let result = try? await Shell.run(
    executable: "git",
    arguments: ["merge-base", "HEAD", "origin/\(baseRefName)"],
    currentDirectory: repoDir,
    timeout: 30
  )
  let mergeBase = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  return mergeBase.isEmpty ? nil : mergeBase
}

func runCodexExecReview(repoDir: URL, prompt: String) async throws -> ReviewOutputEvent {
  let outputFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("pr-reviews-review-output-\(UUID().uuidString).txt")
  defer { try? FileManager.default.removeItem(at: outputFile) }

  _ = try await Shell.run(
    executable: "codex",
    arguments: ["exec", "--json", "--full-auto", "--output-last-message", outputFile.path, "-"],
    currentDirectory: repoDir,
    standardInput: prompt,
    timeout: 1800
  )

  let text = try String(contentsOf: outputFile).trimmingCharacters(in: .whitespacesAndNewlines)
  return try parseReviewOutputEvent(text)
}

func collectChangedDiffLines(repoDir: URL, baseRefName: String) async throws -> [String: FileDiffLines] {
  let result = try await Shell.run(
    executable: "git",
    arguments: ["diff", "--unified=0", "--no-color", "origin/\(baseRefName)...HEAD"],
    currentDirectory: repoDir,
    timeout: 60
  )
  return parseChangedDiffLines(result.stdout)
}

private func parseReviewOutputEvent(_ text: String) throws -> ReviewOutputEvent {
  if let event = try? JSONDecoder().decode(ReviewOutputEvent.self, from: Data(text.utf8)) {
    return event
  }

  if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
    let slice = String(text[start...end])
    if let event = try? JSONDecoder().decode(ReviewOutputEvent.self, from: Data(slice.utf8)) {
      return event
    }
  }

  throw ShellError.nonZeroExit(command: "codex exec", message: "codex exec review output was not valid review JSON")
}

private func parseChangedDiffLines(_ diffText: String) -> [String: FileDiffLines] {
  var changedLines: [String: FileDiffLines] = [:]
  var currentOldPath: String?
  var currentNewPath: String?
  var currentOldLine = 0
  var currentNewLine = 0

  for line in diffText.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = String(line)
    if let header = line.trimmingPrefix("diff --git a/").nonEmpty, let (oldPath, newPath) = header.splitOnce(separator: " b/") {
      currentOldPath = String(oldPath)
      currentNewPath = String(newPath)
      continue
    }

    if let hunk = line.trimmingPrefix("@@ ").nonEmpty {
      guard let (oldPart, rest) = hunk.splitOnce(separator: " ") else { continue }
      currentOldLine = Int(oldPart.trimmingPrefix("-").split(separator: ",").first ?? "0") ?? 0
      let newSpan = rest.trimmingPrefix("+").split(separator: " ").first.map(String.init) ?? ""
      currentNewLine = Int(newSpan.split(separator: ",").first ?? "0") ?? 0
      continue
    }

    if line.hasPrefix("+") && !line.hasPrefix("+++") {
      if let path = currentNewPath {
        changedLines[path, default: FileDiffLines()].right.insert(currentNewLine)
      }
      currentNewLine += 1
      continue
    }

    if line.hasPrefix("-") && !line.hasPrefix("---") {
      if let path = currentOldPath {
        changedLines[path, default: FileDiffLines()].left.insert(currentOldLine)
      }
      currentOldLine += 1
      continue
    }

    if line.hasPrefix(" ") {
      currentOldLine += 1
      currentNewLine += 1
      continue
    }

    if line == "\\ No newline at end of file" {
      continue
    }

    if let path = line.trimmingPrefix("--- a/").nonEmpty {
      changedLines[String(path), default: FileDiffLines()] = changedLines[String(path), default: FileDiffLines()]
      continue
    }

    if let path = line.trimmingPrefix("+++ b/").nonEmpty {
      changedLines[String(path), default: FileDiffLines()] = changedLines[String(path), default: FileDiffLines()]
    }
  }

  return changedLines
}

private func runGit(repoDir: URL, args: [String]) async throws {
  _ = try await Shell.run(executable: "git", arguments: args, currentDirectory: repoDir, timeout: 120)
}

private extension String {
  func splitOnce(separator: String) -> (Substring, Substring)? {
    guard let range = range(of: separator) else { return nil }
    return (self[..<range.lowerBound], self[range.upperBound...])
  }

  func trimmingPrefix(_ prefix: String) -> String {
    guard hasPrefix(prefix) else { return self }
    return String(dropFirst(prefix.count))
  }

  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
