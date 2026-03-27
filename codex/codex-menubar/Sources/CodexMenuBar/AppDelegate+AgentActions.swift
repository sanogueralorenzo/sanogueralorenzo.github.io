import AppKit
import Foundation

extension AppDelegate {
  private static func runAgentSettingsOperation<T: Sendable>(
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

  @objc func createCodexAgent(_ sender: Any?) {
    openRunFromBrowser(sender)
  }

  @objc func openRunFromBrowser(_ sender: Any?) {
    let browserResult = Result { try CurrentBrowserURLReader.frontmostBrowserApplication() }

    if let existingController = codexBrowserRunWindowController {
      existingController.present()
      loadCurrentBrowserTarget(into: existingController, browserResult: browserResult)
      return
    }

    let controller = CodexBrowserRunWindowController(
      onRunReview: { [weak self] pullRequestURL, mode in
        self?.runReviewForPullRequestURL(pullRequestURL, publishMode: mode)
      },
      onRunTask: { [weak self] ticket in
        self?.runTask(ticket: ticket)
      },
      onRunSpike: { [weak self] ticket in
        self?.runSpike(ticket: ticket)
      },
      onClose: { [weak self] in
        self?.codexBrowserRunWindowController = nil
      }
    )

    codexBrowserRunWindowController = controller
    controller.present()
    loadCurrentBrowserTarget(into: controller, browserResult: browserResult)
  }

  @objc func runAgentTask(_ sender: NSMenuItem) {
    guard let ticket = sender.representedObject as? String else {
      return
    }
    runTask(ticket: ticket)
  }

  @objc func rerunCodexAgentTask(_ sender: NSMenuItem) {
    guard let ticket = sender.representedObject as? String else {
      return
    }
    runTask(ticket: ticket)
  }

  @objc func reviewPullRequest(_ sender: NSMenuItem) {
    guard let pullRequestURL = sender.representedObject as? String else {
      return
    }
    runReviewForPullRequestURL(pullRequestURL, publishMode: nil)
  }

  @objc func openAgentURL(_ sender: NSMenuItem) {
    guard let rawURL = sender.representedObject as? String,
      let url = URL(string: rawURL)
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc func openCodexAgentSettings(_ sender: Any?) {
    if let existingController = codexAgentSettingsWindowController {
      existingController.present()
      return
    }

    let sessionsCLI = self.sessionsCLI
    var controller: CodexAgentSettingsWindowController!
    controller = CodexAgentSettingsWindowController(
      onSave: { [weak self] selection in
        guard let self else {
          return
        }

        Task {
          do {
            try await Self.runAgentSettingsOperation {
              try sessionsCLI.setReviewMode(selection.reviewMode)
              try sessionsCLI.setAllowedRepos(selection.allowedRepos)
              try sessionsCLI.setAllowedProjects(selection.allowedProjectIDs)
              try sessionsCLI.setProjectRepoMappings(selection.projectRepoMappings)
            }
            self.refreshUI()
          } catch {
            self.showError(error)
          }
        }
      },
      onClose: { [weak self] in
        self?.codexAgentSettingsWindowController = nil
      },
      onRequestNotifications: { [weak self, weak controller] in
        guard let self, let controller else {
          return
        }
        self.requestNotificationPermission(from: controller)
      }
    )

    codexAgentSettingsWindowController = controller
    controller.present()

    Task {
      do {
        let currentConfig = try await Self.runAgentSettingsOperation {
          try sessionsCLI.agentsConfig()
        }
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        controller.applyCurrentConfig(currentConfig)
      } catch {
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        controller.applyConfigLoadError(message)
        return
      }

      async let integrationStatusesTask: Result<[IntegrationStatus], Swift.Error> =
        loadAgentSettingsResult {
          IntegrationStatusClient.loadAll()
        }
      async let availableReposTask: Result<[CodexCoreCLIClient.AvailableRepo], Swift.Error> =
        loadAgentSettingsResult {
          try sessionsCLI.availableRepos()
        }
      async let availableProjectsTask: Result<[CodexCoreCLIClient.AvailableProject], Swift.Error> =
        loadAgentSettingsResult {
          try sessionsCLI.availableProjects()
        }

      let integrationStatusesResult = await integrationStatusesTask
      if codexAgentSettingsWindowController === controller {
        switch integrationStatusesResult {
        case .success(let statuses):
          controller.applyIntegrationStatuses(statuses)
        case .failure:
          controller.applyIntegrationStatuses([
            IntegrationStatus(
              toolName: "gh",
              state: .error(
                summary: "Error",
                detail: "Unable to determine GitHub CLI status."
              )),
            IntegrationStatus(
              toolName: "acli",
              state: .error(
                summary: "Error",
                detail: "Unable to determine Atlassian CLI status."
              )),
            IntegrationStatus(
              toolName: "notif",
              state: .error(
                summary: "Error",
                detail: "Unable to determine notification permission state."
              )),
          ])
        }
      }

      let availableReposResult = await availableReposTask
      if codexAgentSettingsWindowController === controller {
        switch availableReposResult {
        case .success(let repos):
          controller.applyAvailableRepos(repos)
        case .failure(let error):
          let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
          controller.applyReposLoadError(message)
        }
      }

      let availableProjectsResult = await availableProjectsTask
      if codexAgentSettingsWindowController === controller {
        switch availableProjectsResult {
        case .success(let projects):
          controller.applyAvailableProjects(projects)
        case .failure(let error):
          let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
          controller.applyProjectsLoadError(message)
        }
      }
    }
  }

  @objc func openPullRequests(_ sender: Any?) {
    if let existingController = codexPullRequestsWindowController {
      existingController.present()
      return
    }

    let controller = CodexPullRequestsWindowController(onClose: { [weak self] in
      self?.codexPullRequestsWindowController = nil
    })

    codexPullRequestsWindowController = controller
    controller.present()
  }

  private func runTask(ticket: String) {
    refreshUI()
    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        _ = try sessionsCLI.runTask(ticket: ticket)
        DispatchQueue.main.async {
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self.showError(error)
          self.refreshUI()
        }
      }
    }
  }

  private func requestNotificationPermission(from controller: CodexAgentSettingsWindowController) {
    Task {
      do {
        try await requestNotificationAuthorizationAndSendTest()
      } catch {
        if codexAgentSettingsWindowController === controller {
          showError(error)
        }
      }

      let integrationStatusesResult = await loadAgentSettingsResult {
        IntegrationStatusClient.loadAll()
      }
      if codexAgentSettingsWindowController === controller {
        switch integrationStatusesResult {
        case .success(let statuses):
          controller.applyIntegrationStatuses(statuses)
        case .failure:
          controller.applyIntegrationStatuses([
            IntegrationStatus(
              toolName: "notif",
              state: .error(
                summary: "Error",
                detail: "Unable to determine notification permission state."
              )),
          ])
        }
      }
    }
  }

  private func runSpike(ticket: String) {
    refreshUI()
    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        _ = try sessionsCLI.runSpike(ticket: ticket)
        DispatchQueue.main.async {
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self.showError(error)
          self.refreshUI()
        }
      }
    }
  }

  private func runReviewForPullRequestURL(
    _ pullRequestURL: String,
    publishMode: CodexCoreCLIClient.ReviewMode?
  ) {
    refreshUI()
    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        _ = try sessionsCLI.runReview(
          pullRequest: pullRequestURL,
          publishMode: publishMode
        )
        DispatchQueue.main.async {
          self.refreshUI()
        }
      } catch {
        DispatchQueue.main.async {
          self.showError(error)
          self.refreshUI()
        }
      }
    }
  }

  private func loadCurrentBrowserTarget(
    into controller: CodexBrowserRunWindowController,
    browserResult: Result<BrowserApplication, Swift.Error>
  ) {
    let browser: BrowserApplication
    switch browserResult {
    case .success(let resolvedBrowser):
      browser = resolvedBrowser
    case .failure(let error):
      let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
      controller.applyError(message)
      return
    }

    controller.applyLoading(browserName: browser.displayName)
    let sessionsCLI = self.sessionsCLI

    Task {
      async let targetResult: Result<BrowserRunTarget, Swift.Error> = loadAgentSettingsResult {
        let context = try CurrentBrowserURLReader.readURL(from: browser)
        guard let target = BrowserRunTarget.parse(urlString: context.urlString) else {
          throw CodexCoreCLIClient.Error(
            message: "Open a GitHub pull request or Jira ticket in the current browser tab.")
        }
        return target
      }
      async let configResult: Result<CodexCoreCLIClient.AgentsConfig, Swift.Error> =
        loadAgentSettingsResult {
          try sessionsCLI.agentsConfig()
        }

      let resolvedTarget = await targetResult
      guard codexBrowserRunWindowController === controller else {
        return
      }

      switch resolvedTarget {
      case .success(let target):
        let reviewMode: CodexCoreCLIClient.ReviewMode
        switch await configResult {
        case .success(let config):
          reviewMode = config.reviewMode
        case .failure:
          reviewMode = .publish
        }
        controller.applyTarget(target, defaultReviewMode: reviewMode)

      case .failure(let error):
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        controller.applyError(message)
      }
    }
  }

  private func loadAgentSettingsResult<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
  ) async -> Result<T, Swift.Error> {
    do {
      return .success(try await Self.runAgentSettingsOperation(operation))
    } catch {
      return .failure(error)
    }
  }

}
