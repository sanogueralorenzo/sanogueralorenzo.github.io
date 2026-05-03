import Foundation

struct PullRequestFeedback: Sendable {
  let lines: [String]
}

final class GitHubCLIClient: @unchecked Sendable {
  private let jsonDecoder = JSONDecoder()

  init() {}

  func integrationStatus() async -> IntegrationStatus {
    guard Shell.resolve("gh") != nil else {
      return IntegrationStatus(
        toolName: "gh",
        state: .missing(summary: "gh missing", detail: "Install GitHub CLI and authenticate.")
      )
    }

    do {
      let result = try await Shell.run(executable: "gh", arguments: ["auth", "status"], timeout: 15)
      let line = result.stdout.split(separator: "\n").first.map(String.init) ?? "Authenticated"
      return IntegrationStatus(toolName: "gh", state: .ready(summary: "Authenticated", detail: line))
    } catch {
      return IntegrationStatus(
        toolName: "gh",
        state: .actionNeeded(summary: "Auth required", detail: error.localizedDescription)
      )
    }
  }

  func listPullRequests(repos: [String], filter: PRFilter) async throws -> [PullRequestSummary] {
    var items = [PullRequestSummary]()
    try await withThrowingTaskGroup(of: [PullRequestSummary].self) { group in
      for repo in repos {
        group.addTask {
          try await self.listPullRequests(repo: repo, filter: filter)
        }
      }
      for try await repoItems in group {
        items.append(contentsOf: repoItems)
      }
    }
    return items.sorted { $0.updatedAt > $1.updatedAt }
  }

  func fetchPullRequestFeedback(owner: String, repo: String, number: Int) async throws -> PullRequestFeedback {
    struct PullRequestView: Decodable {
      struct Comment: Decodable { let body: String }
      struct Review: Decodable { let body: String }
      let comments: [Comment]
      let reviews: [Review]
    }

    struct InlineComment: Decodable {
      let body: String
      let path: String?
      let line: Int?
    }

    let viewResult = try await Shell.run(
      executable: "gh",
      arguments: ["pr", "view", String(number), "--repo", "\(owner)/\(repo)", "--json", "comments,reviews"],
      timeout: 30
    )
    let pullRequestView = try jsonDecoder.decode(PullRequestView.self, from: Data(viewResult.stdout.utf8))

    let inlineResult = try await Shell.run(
      executable: "gh",
      arguments: ["api", "repos/\(owner)/\(repo)/pulls/\(number)/comments?per_page=100"],
      timeout: 30
    )
    let inlineComments = (try? jsonDecoder.decode([InlineComment].self, from: Data(inlineResult.stdout.utf8))) ?? []

    let topLevel = pullRequestView.comments.map(\.body) + pullRequestView.reviews.map(\.body)
    let inline = inlineComments.map { comment in
      let location = [comment.path, comment.line.map(String.init)].compactMap { $0 }.joined(separator: ":")
      return location.isEmpty ? comment.body : "\(location) \(comment.body)"
    }

    let lines = (topLevel + inline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return PullRequestFeedback(lines: lines)
  }

  func postPullRequestComment(owner: String, repo: String, number: Int, bodyFile: URL) async throws {
    _ = try await Shell.run(
      executable: "gh",
      arguments: ["pr", "comment", String(number), "--repo", "\(owner)/\(repo)", "--body-file", bodyFile.path],
      timeout: 30
    )
  }

  private func listPullRequests(repo: String, filter: PRFilter) async throws -> [PullRequestSummary] {
    struct ResponseItem: Decodable {
      struct Author: Decodable {
        let login: String
        let name: String?
      }
      struct Comment: Decodable {}
      let number: Int
      let title: String
      let url: String
      let author: Author
      let headRefName: String
      let baseRefName: String
      let isDraft: Bool
      let updatedAt: String
      let comments: [Comment]
    }

    var args = [
      "pr", "list",
      "-R", repo,
      "--state", "open",
      "--limit", "100",
      "--json", "number,title,url,author,headRefName,baseRefName,isDraft,updatedAt,comments"
    ]
    if filter == .yours {
      args.append(contentsOf: ["--author", "@me"])
    }
    let result = try await Shell.run(executable: "gh", arguments: args, timeout: 30)
    let decoded = try jsonDecoder.decode([ResponseItem].self, from: Data(result.stdout.utf8))
    return decoded.map {
      PullRequestSummary(
        repoFullName: repo,
        number: $0.number,
        title: $0.title,
        url: $0.url,
        author: .init(login: $0.author.login, name: $0.author.name),
        headRefName: $0.headRefName,
        baseRefName: $0.baseRefName,
        isDraft: $0.isDraft,
        updatedAt: $0.updatedAt,
        commentCount: $0.comments.count
      )
    }
  }
}
