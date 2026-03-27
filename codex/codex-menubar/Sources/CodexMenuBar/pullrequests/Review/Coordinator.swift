import Foundation

final class ReviewCoordinator: @unchecked Sendable {
  var onSnapshotChange: (@MainActor @Sendable (ReviewJobSnapshot) -> Void)?

  private let paths: AppPaths
  private let fileManager: FileManager
  private let github: ReviewGitHubClient
  private let jobStore: ReviewJobStore

  init(
    paths: AppPaths = AppPaths(),
    github: ReviewGitHubClient = ReviewGitHubClient(),
    jobStore: ReviewJobStore? = nil,
    fileManager: FileManager = .default
  ) {
    self.paths = paths
    self.github = github
    self.fileManager = fileManager
    self.jobStore = jobStore ?? ReviewJobStore(paths: paths)
  }

  func loadJobs() async throws -> [ReviewJobSnapshot] {
    try await jobStore.loadAll()
  }

  func clearFinishedJobs() async throws -> [ReviewJobSnapshot] {
    try await jobStore.clearFinished()
    return try await jobStore.loadAll()
  }

  func runReview(for pullRequest: PullRequestSummary) async throws -> ReviewJobSnapshot {
    guard let reference = PullRequestReference.parse(urlString: pullRequest.url) else {
      throw ShellError.nonZeroExit(command: pullRequest.url, message: "Invalid PR URL")
    }

    var snapshot = try await jobStore.create(reference: reference, pullRequest: pullRequest.url)
    await emit(snapshot)

    var workspace: ReviewWorkspace?
    do {
      snapshot = try await updateStatus(.running, step: "fetching_pr", message: "Loading pull request metadata.", jobID: snapshot.id)
      let pullRequestView = try await github.fetchPullRequestView(reference: reference)

      snapshot = try await jobStore.setPullRequestURL(pullRequestView.url, for: snapshot.id)
      await emit(snapshot)

      snapshot = try await updateStatus(.running, step: "loading_existing_feedback", message: "Loading existing PR comments and review summaries.", jobID: snapshot.id)
      let existingFeedback = try await github.fetchExistingFeedback(reference: reference)

      snapshot = try await updateStatus(.running, step: "loading_prompts", message: "Fetching upstream review prompts.", jobID: snapshot.id)
      let prompts = try await loadUpstreamReviewPrompts(github: github)

      snapshot = try await updateStatus(.running, step: "preparing_repo", message: "Preparing cached repo and review worktree.", jobID: snapshot.id)
      let preparedWorkspace = try await checkoutPullRequest(paths: paths, reference: reference, pullRequest: pullRequestView, fileManager: fileManager)
      workspace = preparedWorkspace

      snapshot = try await updateStatus(.running, step: "resolving_merge_base", message: "Resolving merge base against the PR base branch.", jobID: snapshot.id)
      let mergeBase = try await resolveMergeBase(repoDir: preparedWorkspace.repoDir, baseRefName: pullRequestView.baseRefName)

      let prompt = buildReviewPrompt(
        prompts: prompts,
        pullRequest: pullRequestView,
        mergeBase: mergeBase,
        existingFeedback: existingFeedback
      )

      snapshot = try await updateStatus(.running, step: "running_codex_exec", message: "Running codex exec review.", jobID: snapshot.id)
      let review = try await runCodexExecReview(repoDir: preparedWorkspace.repoDir, prompt: prompt)

      snapshot = try await updateStatus(.running, step: "collecting_diff", message: "Collecting changed diff lines for PR comment validation.", jobID: snapshot.id)
      let changedLines = try await collectChangedDiffLines(repoDir: preparedWorkspace.repoDir, baseRefName: pullRequestView.baseRefName)

      snapshot = try await updateStatus(.postingComments, step: "posting_comments", message: "Creating pending GitHub review.", jobID: snapshot.id)
      let result = try await postPendingReviewComments(
        github: github,
        reference: reference,
        repoDir: preparedWorkspace.repoDir,
        pullRequest: pullRequestView,
        review: review,
        changedLines: changedLines
      )

      let completionStep = result.postedComments > 0 ? "pending_review_created" : "completed"
      snapshot = try await jobStore.complete(result, step: completionStep, for: snapshot.id)
      if let workspace {
        await removeReviewWorktree(workspace, fileManager: fileManager)
      }
      await emit(snapshot)
      return snapshot
    } catch {
      if let workspace {
        await removeReviewWorktree(workspace, fileManager: fileManager)
      }
      snapshot = try await jobStore.fail(error, step: snapshot.currentStep, for: snapshot.id)
      await emit(snapshot)
      throw error
    }
  }

  private func updateStatus(_ status: ReviewJobStatus, step: String, message: String, jobID: String) async throws -> ReviewJobSnapshot {
    let snapshot = try await jobStore.setStatus(status, step: step, message: message, for: jobID)
    await emit(snapshot)
    return snapshot
  }

  private func emit(_ snapshot: ReviewJobSnapshot) async {
    await onSnapshotChange?(snapshot)
  }
}
