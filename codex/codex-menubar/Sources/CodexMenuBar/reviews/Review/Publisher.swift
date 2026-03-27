import Foundation

struct PendingReviewComment: Encodable, Sendable {
  let path: String
  let line: Int
  let side: String
  let body: String
}

func postPendingReviewComments(
  github: ReviewGitHubClient,
  reference: PullRequestReference,
  repoDir: URL,
  pullRequest: ReviewPullRequestView,
  review: ReviewOutputEvent,
  changedLines: [String: FileDiffLines]
) async throws -> ReviewRunResult {
  let summary = summarizeReview(review)
  var pendingComments = [PendingReviewComment]()
  var pendingBodySections = [String]()

  for finding in review.findings {
    let normalizedPath = normalizeCommentPath(finding.codeLocation.absoluteFilePath, repoDir: repoDir)
    let pathForComment = normalizedPath ?? finding.codeLocation.absoluteFilePath
    let body = renderInlineCommentBody(finding)

    if let normalizedPath, let target = selectCommentTarget(lineRange: finding.codeLocation.lineRange, changedLines: changedLines[normalizedPath]) {
      pendingComments.append(
        PendingReviewComment(
          path: normalizedPath,
          line: target.line,
          side: target.side.rawValue,
          body: body
        )
      )
    } else {
      pendingBodySections.append(
        renderTopLevelCommentBody(
          reference: reference,
          headRefOid: pullRequest.headRefOid,
          finding: finding,
          path: pathForComment
        )
      )
    }
  }

  let pendingBody = renderPendingReviewBody(pendingBodySections)
  let totalFindings = review.findings.count
  if totalFindings > 0 {
    try await github.createPendingReview(
      reference: reference,
      headRefOid: pullRequest.headRefOid,
      body: pendingBody,
      comments: pendingComments
    )
  }

  return ReviewRunResult(
    postedComments: totalFindings,
    failedComments: 0,
    failedCommentDetails: [],
    summary: summary,
    url: pullRequest.url
  )
}

private func summarizeReview(_ review: ReviewOutputEvent) -> String {
  let explanation = review.overallExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
  if explanation.isEmpty {
    return review.overallCorrectness
  }
  if review.overallCorrectness.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return explanation
  }
  return "\(review.overallCorrectness.trimmingCharacters(in: .whitespacesAndNewlines)): \(explanation)"
}

private func normalizeCommentPath(_ path: String, repoDir: URL) -> String? {
  let pathURL = URL(fileURLWithPath: path)
  guard pathURL.path.hasPrefix(repoDir.path + "/") else { return nil }
  return String(pathURL.path.dropFirst(repoDir.path.count + 1))
}

private func selectCommentTarget(lineRange: ReviewLineRange, changedLines: FileDiffLines?) -> (line: Int, side: DiffSide)? {
  guard let changedLines else { return nil }
  let end = max(lineRange.end, lineRange.start)
  for line in lineRange.start...end where changedLines.right.contains(line) {
    return (line, .right)
  }
  for line in lineRange.start...end where changedLines.left.contains(line) {
    return (line, .left)
  }
  return nil
}

private func renderInlineCommentBody(_ finding: ReviewFinding) -> String {
  [
    renderFindingHeading(finding),
    "",
    finding.body.trimmingCharacters(in: .whitespacesAndNewlines),
    "Confidence: \(String(format: "%.2f", finding.confidenceScore))",
  ].joined(separator: "\n")
}

private func renderTopLevelCommentBody(
  reference: PullRequestReference,
  headRefOid: String,
  finding: ReviewFinding,
  path: String
) -> String {
  let lineRange = finding.codeLocation.lineRange
  let location = if lineRange.end > lineRange.start {
    "\(path):\(lineRange.start)-\(lineRange.end)"
  } else {
    "\(path):\(lineRange.start)"
  }
  let locationLink = githubBlobLineURL(reference: reference, headRefOid: headRefOid, path: path, lineRange: lineRange)

  return [
    renderFindingHeading(finding),
    "",
    "File: [`\(location)`](\(locationLink))",
    "",
    finding.body.trimmingCharacters(in: .whitespacesAndNewlines),
    "Confidence: \(String(format: "%.2f", finding.confidenceScore))",
  ].joined(separator: "\n")
}

private func renderPendingReviewBody(_ sections: [String]) -> String? {
  let filtered = sections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  return filtered.isEmpty ? nil : filtered.joined(separator: "\n\n---\n\n")
}

private func githubBlobLineURL(
  reference: PullRequestReference,
  headRefOid: String,
  path: String,
  lineRange: ReviewLineRange
) -> String {
  let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  let anchor = if lineRange.end > lineRange.start {
    "#L\(lineRange.start)-L\(lineRange.end)"
  } else {
    "#L\(lineRange.start)"
  }
  return "https://github.com/\(reference.owner)/\(reference.repo)/blob/\(headRefOid)/\(cleanPath)\(anchor)"
}

private func renderFindingHeading(_ finding: ReviewFinding) -> String {
  let title = stripPriorityPrefix(finding.title.trimmingCharacters(in: .whitespacesAndNewlines))
  if let badge = renderPriorityBadgeMarkdown(priority: finding.priority) {
    return "**<sub><sub>\(badge)</sub></sub>  \(title)**"
  }
  return title
}

private func stripPriorityPrefix(_ title: String) -> String {
  for prefix in ["[P0]", "[P1]", "[P2]", "[P3]"] {
    if let remaining = title.trimmingCharacters(in: .whitespacesAndNewlines).splitPrefix(prefix) {
      return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
  return title.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func renderPriorityBadgeMarkdown(priority: Int?) -> String? {
  guard let priority else { return nil }
  let color: String
  switch priority {
  case 0, 1:
    color = "red"
  case 2:
    color = "yellow"
  case 3:
    color = "lightgrey"
  default:
    return nil
  }
  return "![P\(priority) Badge](https://img.shields.io/badge/P\(priority)-\(color)?style=flat)"
}

private extension String {
  func splitPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    return String(dropFirst(prefix.count))
  }
}
