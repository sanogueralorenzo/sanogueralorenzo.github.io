import Foundation

func loadUpstreamReviewPrompts(github: ReviewGitHubClient) async throws -> UpstreamReviewPrompts {
  let reviewRubric = try await github.fetchUpstreamFile(path: "codex-rs/core/review_prompt.md")
  let reviewPromptsSource = try await github.fetchUpstreamFile(path: "codex-rs/core/src/review_prompts.rs")
  return UpstreamReviewPrompts(
    reviewRubric: reviewRubric,
    baseBranchPrompt: try extractRustStringConstant(source: reviewPromptsSource, constantName: "BASE_BRANCH_PROMPT"),
    baseBranchPromptBackup: try extractRustStringConstant(source: reviewPromptsSource, constantName: "BASE_BRANCH_PROMPT_BACKUP")
  )
}

func extractRustStringConstant(source: String, constantName: String) throws -> String {
  let marker = "const \(constantName): &str = "
  guard let start = source.range(of: marker)?.upperBound else {
    throw ShellError.nonZeroExit(command: constantName, message: "Missing upstream constant \(constantName)")
  }
  guard let end = source[start...].firstIndex(of: ";") else {
    throw ShellError.nonZeroExit(command: constantName, message: "Failed to parse upstream constant \(constantName)")
  }
  let rhs = source[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
  guard rhs.first == "\"" else {
    throw ShellError.nonZeroExit(command: constantName, message: "Unsupported upstream constant format for \(constantName)")
  }
  return try JSONDecoder().decode(String.self, from: Data(rhs.utf8))
}

func buildBaseBranchReviewRequest(
  prompts: UpstreamReviewPrompts,
  baseRefName: String,
  mergeBase: String?
) -> String {
  if let mergeBase {
    return prompts.baseBranchPrompt
      .replacingOccurrences(of: "{baseBranch}", with: baseRefName)
      .replacingOccurrences(of: "{mergeBaseSha}", with: mergeBase)
  }

  return prompts.baseBranchPromptBackup
    .replacingOccurrences(of: "{branch}", with: baseRefName)
}

func existingFeedbackPrompt(_ feedback: [ExistingReviewFeedback]) -> String {
  guard !feedback.isEmpty else {
    return """
    Existing PR comments:
    No existing PR comments were found.

    Avoid repeating feedback that is already present on the pull request.
    """
  }

  let rendered = feedback
    .prefix(20)
    .map { "- \(truncateFeedback($0.body, maxCharacters: 600))" }
    .joined(separator: "\n")

  return """
  Existing PR comments:
  \(rendered)

  Avoid repeating feedback that is already present on the pull request unless you are correcting it or adding materially new information.
  """
}

func buildReviewPrompt(
  prompts: UpstreamReviewPrompts,
  pullRequest: ReviewPullRequestView,
  mergeBase: String?,
  existingFeedback: [ExistingReviewFeedback]
) -> String {
  let reviewRequest = buildBaseBranchReviewRequest(
    prompts: prompts,
    baseRefName: pullRequest.baseRefName,
    mergeBase: mergeBase
  )

  return [
    prompts.reviewRubric,
    reviewRequest,
    existingFeedbackPrompt(existingFeedback),
    "Formatting:\n- Format file names, classes, methods, and variables as inline code. Use file:line only when pointing to a concrete location that matters.",
  ].joined(separator: "\n\n")
}

private func truncateFeedback(_ value: String, maxCharacters: Int) -> String {
  guard value.count > maxCharacters else { return value }
  let index = value.index(value.startIndex, offsetBy: maxCharacters)
  return String(value[..<index]) + "..."
}
