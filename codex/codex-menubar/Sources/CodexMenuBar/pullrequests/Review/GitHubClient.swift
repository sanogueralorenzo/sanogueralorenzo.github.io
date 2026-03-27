import Foundation

final class ReviewGitHubClient: @unchecked Sendable {
  private let decoder = JSONDecoder()

  func fetchPullRequestView(reference: PullRequestReference) async throws -> ReviewPullRequestView {
    let result = try await Shell.run(
      executable: "gh",
      arguments: [
        "pr", "view", String(reference.number),
        "--repo", reference.repoFullName,
        "--json", "number,title,url,baseRefName,headRefName,headRefOid",
      ],
      timeout: 30
    )
    return try decoder.decode(ReviewPullRequestView.self, from: Data(result.stdout.utf8))
  }

  func fetchExistingFeedback(reference: PullRequestReference) async throws -> [ExistingReviewFeedback] {
    struct FeedbackView: Decodable {
      struct Comment: Decodable { let body: String }
      struct Review: Decodable { let body: String }
      let comments: [Comment]
      let reviews: [Review]
    }

    let result = try await Shell.run(
      executable: "gh",
      arguments: [
        "pr", "view", String(reference.number),
        "--repo", reference.repoFullName,
        "--json", "comments,reviews",
      ],
      timeout: 30
    )
    let view = try decoder.decode(FeedbackView.self, from: Data(result.stdout.utf8))
    let bodies = (view.comments.map(\.body) + view.reviews.map(\.body))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return bodies.map { ExistingReviewFeedback(body: $0) }
  }

  func fetchUpstreamFile(path: String) async throws -> String {
    let result = try await Shell.run(
      executable: "gh",
      arguments: [
        "api",
        "repos/openai/codex/contents/\(path)?ref=main",
        "-H", "Accept: application/vnd.github.raw",
      ],
      timeout: 30
    )
    return result.stdout
  }

  func createPendingReview(
    reference: PullRequestReference,
    headRefOid: String,
    body: String?,
    comments: [PendingReviewComment]
  ) async throws {
    struct Payload: Encodable {
      let commit_id: String
      let body: String?
      let comments: [PendingReviewComment]?
    }

    guard (body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) || !comments.isEmpty else {
      return
    }

    let payload = Payload(
      commit_id: headRefOid,
      body: body?.trimmingCharacters(in: .whitespacesAndNewlines),
      comments: comments.isEmpty ? nil : comments
    )
    let payloadFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("pr-reviews-pending-review-\(UUID().uuidString).json")
    let data = try JSONEncoder().encode(payload)
    try data.write(to: payloadFile, options: .atomic)
    defer { try? FileManager.default.removeItem(at: payloadFile) }

    _ = try await Shell.run(
      executable: "gh",
      arguments: [
        "api",
        "repos/\(reference.owner)/\(reference.repo)/pulls/\(reference.number)/reviews",
        "-H", "Accept: application/vnd.github+json",
        "--input", payloadFile.path,
      ],
      timeout: 30
    )
  }
}
