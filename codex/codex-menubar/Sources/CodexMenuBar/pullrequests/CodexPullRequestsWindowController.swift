import AppKit
import Foundation

@MainActor
final class CodexPullRequestsWindowController: NSWindowController, NSWindowDelegate {
  private let github = GitHubCLIClient()
  private let paths = AppPaths()
  private lazy var codexRunner = CodexActionRunner(paths: paths, github: github)
  private lazy var reviewCoordinator = ReviewCoordinator(paths: paths)
  private let configStore = ConfigStore()
  private let activityStore = ActivityStore()
  private let onClose: () -> Void
  private let onNotify: @MainActor (_ title: String, _ message: String, _ targetURL: String?) -> Void

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
  private var reviewJobsByURL: [String: ReviewJobSnapshot] = [:]
  private var currentItems: [PullRequestSummary] = []
  private var isLoading = false
  private var currentError: String?
  private var refreshGeneration = 0
  private var hasLoadedInitialState = false

  init(
    onClose: @escaping () -> Void,
    onNotify: @escaping @MainActor (_ title: String, _ message: String, _ targetURL: String?) -> Void
  ) {
    self.onClose = onClose
    self.onNotify = onNotify

    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: PRReviewsViewController.preferredSize),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Pull Requests"
    panel.isFloatingPanel = true
    panel.center()
    panel.minSize = PRReviewsViewController.preferredSize
    panel.setFrameAutosaveName("CodexPullRequestsPanel")

    super.init(window: panel)

    panel.delegate = self
    panel.contentViewController = reviewsViewController

    reviewCoordinator.onSnapshotChange = { [weak self] snapshot in
      self?.handleReviewJobSnapshotChange(snapshot)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)

    if hasLoadedInitialState {
      applyCurrentState()
      Task { await refreshPullRequests() }
      return
    }

    hasLoadedInitialState = true
    Task { await loadInitialState() }
  }

  func windowWillClose(_ notification: Notification) {
    reviewsViewController.resetToMainScreen()
    onClose()
  }

  private func loadInitialState() async {
    do {
      config = try await configStore.load()
      activities = try await activityStore.load()
      setReviewJobs(try await reviewCoordinator.loadJobs())
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
            return job.status == .completed
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
      let repos = try await github.listAvailableRepos()
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
    config.allowedRepos = repos
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
      setReviewJobs(try await reviewCoordinator.clearFinishedJobs())
      applyCurrentState()
    } catch {
      currentError = error.localizedDescription
      applyCurrentState()
    }
  }

  private func runAction(for pullRequest: PullRequestSummary, filter: PRFilter) async {
    if filter == .all {
      do {
        _ = try await reviewCoordinator.runReview(for: pullRequest)
      } catch {
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
      case .queued, .running, .postingComments:
        .running
      case .completed:
        .completed
      case .failed:
        .failed
      }

      combined[url] = ActivityRecord(
        pullRequestURL: url,
        kind: .review,
        status: status,
        detail: job.summary ?? job.error,
        updatedAt: job.finishedAt ?? job.startedAt ?? job.createdAt
      )
    }

    return combined
  }

  private func setReviewJobs(_ jobs: [ReviewJobSnapshot]) {
    reviewJobsByURL = Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
      guard let url = job.url else {
        return nil
      }
      return (url, job)
    })
  }

  private func handleReviewJobSnapshotChange(_ snapshot: ReviewJobSnapshot) {
    let previousStatus = snapshot.url.flatMap { reviewJobsByURL[$0]?.status }

    if let url = snapshot.url {
      reviewJobsByURL[url] = snapshot
    }

    if previousStatus != snapshot.status {
      let title: String = switch snapshot.status {
      case .queued, .running, .postingComments:
        "Review Started"
      case .completed:
        "Review Completed"
      case .failed:
        "Review Failed"
      }
      onNotify(title, "PR: #\(snapshot.number)", snapshot.filesURL?.absoluteString)
    }

    if snapshot.status == .failed {
      currentError = snapshot.error
    }

    if currentFilter == .reviews && snapshot.status == .completed {
      Task { await refreshPullRequests() }
      return
    }

    applyCurrentState()
  }
}
