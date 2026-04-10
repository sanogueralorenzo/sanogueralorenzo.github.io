import AppKit
import Foundation

@MainActor
final class CodexPullRequestsWindowController: NSObject, NSPopoverDelegate {
  private let github = GitHubCLIClient()
  private let sessionsCLI = CodexCoreCLIClient()
  private let paths = AppPaths()
  private lazy var codexRunner = CodexActionRunner(paths: paths, github: github)
  private let configStore = ConfigStore()
  private let activityStore = ActivityStore()
  private let onClose: () -> Void
  private let onReviewJobsChanged: @MainActor () -> Void
  private let popover = NSPopover()

  private lazy var reviewsViewController = PRReviewsViewController(
    onShowSettings: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.refreshSettingsPanel()
      }
    },
    onClear: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.clearFinishedActivities()
      }
    },
    onFilterChange: { [weak self] filter in
      self?.currentFilter = filter
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.refreshPullRequests()
      }
    },
    onAction: { [weak self] pullRequest, filter in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.runAction(for: pullRequest, filter: filter)
      }
    },
    onSelectionChange: { [weak self] repos in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.updateSelectedRepos(repos)
      }
    },
    onThresholdChange: { [weak self] threshold in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.updateMinimumCommentsForApplyFeedback(threshold)
      }
    }
  )

  private var currentFilter: PRFilter = .all
  private var config = AppConfig.default
  private var activities: [String: ActivityRecord] = [:]
  private var reviewJobsByURL: [String: CodexCoreCLIClient.ReviewJob] = [:]
  private var currentItems: [PullRequestSummary] = []
  private var isLoading = false
  private var currentError: String?
  private var refreshGeneration = 0
  private var hasLoadedInitialState = false

  init(
    onClose: @escaping () -> Void,
    onReviewJobsChanged: @escaping @MainActor () -> Void
  ) {
    self.onClose = onClose
    self.onReviewJobsChanged = onReviewJobsChanged
    super.init()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    popover.contentViewController = reviewsViewController
    popover.contentSize = PRReviewsViewController.preferredSize
  }

  func present(relativeTo positioningRect: NSRect, of view: NSView) {
    if popover.isShown {
      popover.performClose(nil)
      return
    }

    popover.appearance = view.window?.effectiveAppearance
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: positioningRect, of: view, preferredEdge: .maxY)

    if hasLoadedInitialState {
      applyCurrentState()
      Task { await refreshPullRequests() }
      return
    }

    hasLoadedInitialState = true
    Task { await loadInitialState() }
  }

  func popoverDidClose(_ notification: Notification) {
    reviewsViewController.resetToMainScreen()
    onClose()
  }

  private func loadInitialState() async {
    do {
      config = try await configStore.load()
      activities = try await activityStore.load()
      config.allowedRepos = try await loadAgentsConfig().allowedRepos
      setReviewJobs(try await loadReviewJobs())
    } catch {
      currentError = error.localizedDescription
    }
    await refreshPullRequests()
  }

  private func refreshPullRequests() async {
    refreshGeneration += 1
    let generation = refreshGeneration

    isLoading = true
    currentError = nil
    currentItems = []
    applyCurrentState()

    do {
      let reviewJobs = try await loadReviewJobs()
      setReviewJobs(reviewJobs)

      let repos = config.allowedRepos
      let items: [PullRequestSummary] =
        if repos.isEmpty {
          []
        } else if currentFilter == .reviews {
          try await github.listPullRequests(repos: repos, filter: .all)
        } else {
          try await github.listPullRequests(repos: repos, filter: currentFilter)
        }

      guard generation == refreshGeneration else {
        return
      }

      currentItems =
        if currentFilter == .reviews {
          items.filter {
            guard let job = reviewJobsByURL[$0.url] else {
              return false
            }
            return job.status == .published
          }
        } else {
          items
        }
      currentError = nil
    } catch {
      guard generation == refreshGeneration else {
        return
      }
      currentItems = []
      currentError = error.localizedDescription
    }

    guard generation == refreshGeneration else {
      return
    }

    isLoading = false
    applyCurrentState()
  }

  private func refreshSettingsPanel() async {
    reviewsViewController.applySettingsState(
      statuses: [
        IntegrationStatus(toolName: "gh", state: .checking),
        IntegrationStatus(toolName: "codex", state: .checking),
      ],
      availableRepos: [],
      selectedRepos: config.allowedRepos,
      minimumCommentsForApplyFeedback: config.minimumCommentsForApplyFeedback,
      isLoading: true
    )

    async let ghStatus = github.integrationStatus()
    async let codexStatus = codexRunner.integrationStatus()
    let statuses = await [ghStatus, codexStatus]

    do {
      let repos = try await loadAvailableRepos()
      reviewsViewController.applySettingsState(
        statuses: statuses,
        availableRepos: repos,
        selectedRepos: config.allowedRepos,
        minimumCommentsForApplyFeedback: config.minimumCommentsForApplyFeedback,
        isLoading: false
      )
    } catch {
      reviewsViewController.applySettingsState(
        statuses: statuses,
        availableRepos: [],
        selectedRepos: config.allowedRepos,
        minimumCommentsForApplyFeedback: config.minimumCommentsForApplyFeedback,
        isLoading: false
      )
    }
  }

  private func updateSelectedRepos(_ repos: [String]) async {
    do {
      try await setAllowedRepos(repos)
      config.allowedRepos = repos
    } catch {
      currentError = error.localizedDescription
    }
    await saveConfigAndRefresh()
  }

  private func updateMinimumCommentsForApplyFeedback(_ threshold: Int) async {
    config.minimumCommentsForApplyFeedback = max(0, threshold)
    await saveConfigAndRefresh()
  }

  private func saveConfigAndRefresh() async {
    do {
      try await configStore.save(config)
    } catch {
      currentError = error.localizedDescription
    }
    await refreshPullRequests()
    await refreshSettingsPanel()
  }

  private func clearFinishedActivities() async {
    do {
      activities = try await activityStore.clearFinished()
      try await clearFinishedReviewJobs()
      await refreshPullRequests()
    } catch {
      currentError = error.localizedDescription
      applyCurrentState()
    }
  }

  private func runAction(for pullRequest: PullRequestSummary, filter: PRFilter) async {
    if filter == .all {
      await upsertActivity(
        ActivityRecord(
          pullRequestURL: pullRequest.url,
          kind: .review,
          status: .running,
          detail: nil,
          updatedAt: ISO8601DateFormatter().string(from: .now)
        )
      )

      do {
        let result = try await runReview(pullRequestURL: pullRequest.url)
        onReviewJobsChanged()
        await upsertActivity(
          ActivityRecord(
            pullRequestURL: pullRequest.url,
            kind: .review,
            status: .completed,
            detail: result.summary,
            updatedAt: ISO8601DateFormatter().string(from: .now)
          )
        )
        await refreshPullRequests()
      } catch {
        onReviewJobsChanged()
        await upsertActivity(
          ActivityRecord(
            pullRequestURL: pullRequest.url,
            kind: .review,
            status: .failed,
            detail: error.localizedDescription,
            updatedAt: ISO8601DateFormatter().string(from: .now)
          )
        )
        currentError = error.localizedDescription
        applyCurrentState()
      }
      return
    }

    if filter == .reviews {
      if let url = URL(string: pullRequest.filesURL) {
        NSWorkspace.shared.open(url)
      }
      return
    }

    let kind: JobKind = .applyFeedback
    await upsertActivity(
      ActivityRecord(
        pullRequestURL: pullRequest.url,
        kind: kind,
        status: .running,
        detail: nil,
        updatedAt: ISO8601DateFormatter().string(from: .now)
      )
    )

    do {
      let detail = try await codexRunner.runApplyFeedback(for: pullRequest)

      await upsertActivity(
        ActivityRecord(
          pullRequestURL: pullRequest.url,
          kind: kind,
          status: .completed,
          detail: detail,
          updatedAt: ISO8601DateFormatter().string(from: .now)
        )
      )
    } catch {
      await upsertActivity(
        ActivityRecord(
          pullRequestURL: pullRequest.url,
          kind: kind,
          status: .failed,
          detail: error.localizedDescription,
          updatedAt: ISO8601DateFormatter().string(from: .now)
        )
      )
      currentError = error.localizedDescription
      applyCurrentState()
    }
  }

  private func upsertActivity(_ record: ActivityRecord) async {
    do {
      activities = try await activityStore.upsert(record)
      applyCurrentState()
    } catch {
      currentError = error.localizedDescription
      applyCurrentState()
    }
  }

  private func applyCurrentState() {
    reviewsViewController.applyState(
      filter: currentFilter,
      items: currentItems,
      activities: rowActivities(),
      minimumCommentsForApplyFeedback: config.minimumCommentsForApplyFeedback,
      isLoading: isLoading,
      error: currentError
    )
  }

  private func rowActivities() -> [String: ActivityRecord] {
    var combined = activities
    guard currentFilter != .yours else {
      return combined
    }

    for (url, job) in reviewJobsByURL {
      let status: JobStatus = switch job.status {
      case .inProgress:
        .running
      case .published:
        .completed
      case .needsAttention:
        .failed
      }

      combined[url] = ActivityRecord(
        pullRequestURL: url,
        kind: .review,
        status: status,
        detail: job.summary,
        updatedAt: job.createdAt
      )
    }

    return combined
  }

  private func setReviewJobs(_ jobs: [CodexCoreCLIClient.ReviewJob]) {
    var jobsByURL: [String: CodexCoreCLIClient.ReviewJob] = [:]

    for job in jobs {
      guard let url = job.url else {
        continue
      }
      guard let existingJob = jobsByURL[url] else {
        jobsByURL[url] = job
        continue
      }

      if shouldReplaceReviewJob(existingJob, with: job) {
        jobsByURL[url] = job
      }
    }

    reviewJobsByURL = jobsByURL
  }

  private func shouldReplaceReviewJob(
    _ current: CodexCoreCLIClient.ReviewJob,
    with candidate: CodexCoreCLIClient.ReviewJob
  ) -> Bool {
    if current.status != .inProgress && candidate.status == .inProgress {
      return true
    }

    if current.status == .inProgress && candidate.status != .inProgress {
      return false
    }

    return candidate.createdAt > current.createdAt
  }

  private func loadAgentsConfig() async throws -> CodexCoreCLIClient.AgentsConfig {
    let sessionsCLI = self.sessionsCLI
    return try await Self.runCLIOperation {
      try sessionsCLI.agentsConfig()
    }
  }

  private func loadReviewJobs() async throws -> [CodexCoreCLIClient.ReviewJob] {
    let sessionsCLI = self.sessionsCLI
    return try await Self.runCLIOperation {
      try sessionsCLI.listReviewJobs()
    }
  }

  private func loadAvailableRepos() async throws -> [AvailableRepo] {
    let sessionsCLI = self.sessionsCLI
    let repos = try await Self.runCLIOperation {
      try sessionsCLI.availableRepos()
    }
    return repos.map { AvailableRepo(fullName: $0.fullName) }
  }

  private func setAllowedRepos(_ repos: [String]) async throws {
    let sessionsCLI = self.sessionsCLI
    try await Self.runCLIOperation {
      try sessionsCLI.setAllowedRepos(repos)
    }
  }

  private func runReview(pullRequestURL: String) async throws -> CodexCoreCLIClient.ReviewRunResult {
    let sessionsCLI = self.sessionsCLI
    return try await Self.runCLIOperation {
      try sessionsCLI.runReview(pullRequest: pullRequestURL)
    }
  }

  private func clearFinishedReviewJobs() async throws {
    let reviewJobs = try await loadReviewJobs()
    let finishedJobIDs = reviewJobs
      .filter { $0.status != .inProgress }
      .map(\.id)

    guard !finishedJobIDs.isEmpty else {
      return
    }

    let reviewsDirectoryURL = reviewStatusDirectoryURL()
    try await Self.runCLIOperation {
      let fileManager = FileManager.default
      for jobID in finishedJobIDs {
        let path = reviewsDirectoryURL.appendingPathComponent(jobID, isDirectory: true)
        if fileManager.fileExists(atPath: path.path) {
          try fileManager.removeItem(at: path)
        }
      }
    }
  }

  private func reviewStatusDirectoryURL() -> URL {
    if let configuredHome = ProcessInfo.processInfo.environment["CODEX_AGENTS_HOME"],
      !configuredHome.isEmpty
    {
      return URL(fileURLWithPath: configuredHome, isDirectory: true)
        .appendingPathComponent("reviews", isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("agents", isDirectory: true)
      .appendingPathComponent("reviews", isDirectory: true)
  }

  private static func runCLIOperation<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          continuation.resume(returning: try operation())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
