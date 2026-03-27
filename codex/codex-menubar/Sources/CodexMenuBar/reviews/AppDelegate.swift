import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let github = GitHubCLIClient()
  private let paths = AppPaths()
  private lazy var codexRunner = CodexActionRunner(paths: paths, github: github)
  private lazy var reviewCoordinator = ReviewCoordinator(paths: paths)
  private let configStore = ConfigStore()
  private let activityStore = ActivityStore()
  private let notificationController = AppNotificationController()

  private var statusItem: NSStatusItem!
  private var reviewsPopover: NSPopover?
  private var reviewsViewController: PRReviewsViewController?

  private var currentFilter: PRFilter = .all
  private var config = AppConfig.default
  private var activities: [String: ActivityRecord] = [:]
  private var reviewJobsByURL: [String: ReviewJobSnapshot] = [:]
  private var currentItems: [PullRequestSummary] = []
  private var isLoading = false
  private var currentError: String?
  private var refreshGeneration = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    reviewCoordinator.onSnapshotChange = { [weak self] snapshot in
      self?.handleReviewJobSnapshotChange(snapshot)
    }
    notificationController.configure()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "PR"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel(_:))
    statusItem.button?.sendAction(on: [.leftMouseUp])
    Task { await loadInitialState() }
  }

  @objc private func togglePanel(_ sender: Any?) {
    if let reviewsPopover, reviewsPopover.isShown {
      reviewsPopover.performClose(sender)
      return
    }

    if reviewsViewController == nil {
      reviewsViewController = PRReviewsViewController(
        onShowSettings: { [weak self] in
          Task { await self?.refreshSettingsPanel() }
        },
        onClear: { [weak self] in
          Task { await self?.clearFinishedActivities() }
        },
        onFilterChange: { [weak self] filter in
          self?.currentFilter = filter
          Task { await self?.refreshPullRequests() }
        },
        onAction: { [weak self] pullRequest, filter in
          Task { await self?.runAction(for: pullRequest, filter: filter) }
        },
        onSelectionChange: { [weak self] repos in
          Task { await self?.updateSelectedRepos(repos) }
        },
        onThresholdChange: { [weak self] threshold in
          Task { await self?.updateMinimumCommentsForApplyFeedback(threshold) }
        }
      )
    }

    if reviewsPopover == nil {
      let popover = NSPopover()
      popover.behavior = .transient
      popover.animates = true
      popover.delegate = self
      popover.contentViewController = reviewsViewController
      popover.contentSize = PRReviewsViewController.preferredSize
      reviewsPopover = popover
    }

    applyCurrentState()
    guard let button = statusItem.button, let reviewsPopover else { return }
    Task { await self.refreshPullRequests() }
    reviewsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
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
      guard generation == refreshGeneration else { return }
      currentItems =
        if currentFilter == .reviews {
          items.filter {
            guard let job = reviewJobsByURL[$0.url] else { return false }
            return job.status == .completed
          }
        } else {
          items
        }
      currentError = nil
    } catch {
      guard generation == refreshGeneration else { return }
      currentItems = []
      currentError = error.localizedDescription
    }

    guard generation == refreshGeneration else { return }
    isLoading = false
    applyCurrentState()
  }

  private func refreshSettingsPanel() async {
    reviewsViewController?.applySettingsState(
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
      reviewsViewController?.applySettingsState(
        statuses: statuses,
        availableRepos: repos,
        selectedRepos: config.allowedRepos,
        minimumCommentsForApplyFeedback: config.minimumCommentsForApplyFeedback,
        isLoading: false
      )
    } catch {
      reviewsViewController?.applySettingsState(
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
    reviewsViewController?.applyState(
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
    guard currentFilter != .yours else { return combined }
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
      guard let url = job.url else { return nil }
      return (url, job)
    })
  }

  private func handleReviewJobSnapshotChange(_ snapshot: ReviewJobSnapshot) {
    let previous = snapshot.url.flatMap { reviewJobsByURL[$0] }
    if let url = snapshot.url {
      reviewJobsByURL[url] = snapshot
    }
    if previous?.status != snapshot.status {
      notificationController.postReviewNotification(snapshot: snapshot)
    }
    if snapshot.status == .failed {
      currentError = snapshot.error
    }
    if currentFilter == .reviews && snapshot.status == .completed {
      Task { await self.refreshPullRequests() }
      return
    }
    applyCurrentState()
  }

  func popoverDidClose(_ notification: Notification) {
    reviewsViewController?.resetToMainScreen()
  }
}
