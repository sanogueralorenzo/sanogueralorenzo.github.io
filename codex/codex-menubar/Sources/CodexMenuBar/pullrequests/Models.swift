import Foundation

enum PRFilter: Int, CaseIterable, Sendable {
  case all
  case yours
  case reviews

  var title: String {
    switch self {
    case .all: return "All"
    case .yours: return "Yours"
    case .reviews: return "Ready"
    }
  }
}

struct AppConfig: Codable, Sendable {
  var allowedRepos: [String]
  var minimumCommentsForApplyFeedback: Int

  static let `default` = AppConfig(allowedRepos: [], minimumCommentsForApplyFeedback: 0)

  private enum CodingKeys: String, CodingKey {
    case allowedRepos
    case minimumCommentsForApplyFeedback
  }

  init(allowedRepos: [String], minimumCommentsForApplyFeedback: Int) {
    self.allowedRepos = allowedRepos
    self.minimumCommentsForApplyFeedback = minimumCommentsForApplyFeedback
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    allowedRepos = try container.decodeIfPresent([String].self, forKey: .allowedRepos) ?? []
    minimumCommentsForApplyFeedback =
      try container.decodeIfPresent(Int.self, forKey: .minimumCommentsForApplyFeedback) ?? 0
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(allowedRepos, forKey: .allowedRepos)
    try container.encode(minimumCommentsForApplyFeedback, forKey: .minimumCommentsForApplyFeedback)
  }
}

struct AvailableRepo: Codable, Sendable, Hashable {
  let fullName: String
}

struct PullRequestSummary: Codable, Sendable, Hashable {
  struct Author: Codable, Sendable, Hashable {
    let login: String
    let name: String?
  }

  let repoFullName: String
  let number: Int
  let title: String
  let url: String
  let author: Author
  let headRefName: String
  let baseRefName: String
  let isDraft: Bool
  let updatedAt: String
  let commentCount: Int

  var id: String { url }
  var authorDisplayName: String { author.name?.isEmpty == false ? author.name! : author.login }
  var metaLine: String { "\(author.login)   #\(number)   \(headRefName)" }
  var filesURL: String { "\(url)/files" }
}

enum IntegrationState: Equatable, Sendable {
  case checking
  case ready(summary: String, detail: String?)
  case actionNeeded(summary: String, detail: String)
  case missing(summary: String, detail: String)
  case error(summary: String, detail: String)
}

struct IntegrationStatus: Equatable, Sendable {
  let toolName: String
  let state: IntegrationState
}

enum JobKind: String, Codable, Sendable {
  case review
  case applyFeedback
}

enum JobStatus: String, Codable, Sendable {
  case running
  case completed
  case failed
}

struct ActivityRecord: Codable, Sendable {
  let pullRequestURL: String
  let kind: JobKind
  let status: JobStatus
  let detail: String?
  let updatedAt: String
}
