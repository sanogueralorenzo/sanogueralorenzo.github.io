import Foundation

struct ReviewPullRequestView: Decodable, Sendable {
  let number: Int
  let url: String
  let title: String
  let baseRefName: String
  let headRefName: String
  let headRefOid: String
}

struct ExistingReviewFeedback: Sendable {
  let body: String
}

struct UpstreamReviewPrompts: Sendable {
  let reviewRubric: String
  let baseBranchPrompt: String
  let baseBranchPromptBackup: String
}

struct ReviewOutputEvent: Decodable, Sendable {
  let findings: [ReviewFinding]
  let overallCorrectness: String
  let overallExplanation: String

  private enum CodingKeys: String, CodingKey {
    case findings
    case overallCorrectness = "overall_correctness"
    case overallExplanation = "overall_explanation"
  }
}

struct ReviewFinding: Decodable, Sendable {
  let title: String
  let body: String
  let confidenceScore: Float
  let priority: Int?
  let codeLocation: ReviewCodeLocation

  private enum CodingKeys: String, CodingKey {
    case title
    case body
    case confidenceScore = "confidence_score"
    case priority
    case codeLocation = "code_location"
  }
}

struct ReviewCodeLocation: Decodable, Sendable {
  let absoluteFilePath: String
  let lineRange: ReviewLineRange

  private enum CodingKeys: String, CodingKey {
    case absoluteFilePath = "absolute_file_path"
    case lineRange = "line_range"
  }
}

struct ReviewLineRange: Decodable, Encodable, Sendable {
  let start: Int
  let end: Int
}

enum ReviewJobStatus: String, Codable, Sendable {
  case queued
  case running
  case postingComments = "posting_comments"
  case completed
  case failed
}

struct ReviewCommentFailure: Codable, Sendable {
  let title: String
  let path: String?
  let startLine: Int
  let endLine: Int
  let reason: String

  private enum CodingKeys: String, CodingKey {
    case title
    case path
    case startLine = "start_line"
    case endLine = "end_line"
    case reason
  }
}

struct ReviewJobSnapshot: Codable, Sendable {
  let id: String
  let pullRequest: String
  let owner: String
  let repo: String
  let number: Int
  var url: String?
  var status: ReviewJobStatus
  var currentStep: String
  let createdAt: String
  var startedAt: String?
  var finishedAt: String?
  var postedComments: Int
  var failedComments: Int
  var failedCommentDetails: [ReviewCommentFailure]
  var summary: String?
  var error: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case pullRequest = "pull_request"
    case owner
    case repo
    case number
    case url
    case status
    case currentStep = "current_step"
    case createdAt = "created_at"
    case startedAt = "started_at"
    case finishedAt = "finished_at"
    case postedComments = "posted_comments"
    case failedComments = "failed_comments"
    case failedCommentDetails = "failed_comment_details"
    case summary
    case error
  }

  var isFinished: Bool {
    switch status {
    case .completed, .failed:
      return true
    case .queued, .running, .postingComments:
      return false
    }
  }

  var filesURL: URL? {
    guard let url, let value = URL(string: url) else { return nil }
    return value.appending(path: "files")
  }
}

struct ReviewRunResult: Sendable {
  let postedComments: Int
  let failedComments: Int
  let failedCommentDetails: [ReviewCommentFailure]
  let summary: String
  let url: String
}

struct ReviewJobEvent: Codable, Sendable {
  let timestamp: String
  let kind: String
  let step: String
  let message: String
}
