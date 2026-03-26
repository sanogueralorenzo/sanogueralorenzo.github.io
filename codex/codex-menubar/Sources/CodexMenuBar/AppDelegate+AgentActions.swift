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
    // Intentionally no-op placeholder for upcoming Codex Agent flow.
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

    refreshUI()
    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let result = try sessionsCLI.runReview(pullRequest: pullRequestURL)
        DispatchQueue.main.async {
          self.showMessage(
            title: "Review Complete",
            message: self.reviewCompletionMessage(for: result)
          )
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
    let controller = CodexAgentSettingsWindowController(
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
            }
            self.refreshUI()
          } catch {
            self.showError(error)
          }
        }
      },
      onClose: { [weak self] in
        self?.codexAgentSettingsWindowController = nil
      }
    )

    codexAgentSettingsWindowController = controller
    controller.present()

    Task {
      do {
        async let currentConfigTask = Self.runAgentSettingsOperation {
          try sessionsCLI.agentsConfig()
        }
        async let integrationStatusesTask = Self.runAgentSettingsOperation {
          IntegrationStatusClient.loadAll()
        }
        async let availableReposTask = Self.runAgentSettingsOperation {
          try sessionsCLI.availableRepos()
        }
        async let availableProjectsTask = Self.runAgentSettingsOperation {
          try sessionsCLI.availableProjects()
        }

        let currentConfig = try await currentConfigTask
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        controller.applyCurrentConfig(currentConfig)

        let integrationStatuses = try await integrationStatusesTask
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        controller.applyIntegrationStatuses(integrationStatuses)

        let availableRepos = try await availableReposTask
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        controller.applyAvailableRepos(availableRepos)

        let availableProjects = try await availableProjectsTask
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        controller.applyAvailableProjects(availableProjects)
      } catch {
        guard codexAgentSettingsWindowController === controller else {
          return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        controller.applyLoadError(message)
      }
    }
  }

  private func runTask(ticket: String) {
    refreshUI()
    let sessionsCLI = self.sessionsCLI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let result = try sessionsCLI.runTask(ticket: ticket)
        DispatchQueue.main.async {
          self.showMessage(
            title: "Task Complete",
            message: self.taskCompletionMessage(for: result)
          )
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

  private func taskCompletionMessage(for result: CodexCoreCLIClient.TaskRunResult) -> String {
    let prLine = result.prURL.map { "PR: \($0)\n" } ?? ""
    return """
      Task ID: \(result.taskID)
      Ticket: \(result.ticket)
      Repo: \(result.repoFullName)
      Branch: \(result.branch)
      \(prLine)Summary: \(result.summary)
      """
  }

  private func reviewCompletionMessage(for result: CodexCoreCLIClient.ReviewRunResult) -> String {
    let postedLabel = result.publishMode == .pending ? "Pending findings" : "Posted comments"
    return """
      Review ID: \(result.reviewId)
      Review mode: \(result.publishMode.rawValue)
      PR: \(result.repo)#\(result.number)
      \(postedLabel): \(result.postedComments)
      Failed comments: \(result.failedComments)
      Summary: \(result.summary)\(reviewFailureText(for: result))
      """
  }

  private func reviewFailureText(for result: CodexCoreCLIClient.ReviewRunResult) -> String {
    let failureDetails = result.failedCommentDetails.prefix(5).map { detail in
      let path = detail.path ?? "<unknown>"
      return "- \(detail.title) (\(path):\(detail.startLine)-\(detail.endLine)): \(detail.reason)"
    }
    guard !failureDetails.isEmpty else {
      return ""
    }

    let extraCount = result.failedCommentDetails.count - failureDetails.count
    let extraSuffix = extraCount > 0 ? "\n- ... and \(extraCount) more" : ""
    return "\nFailure reasons:\n\(failureDetails.joined(separator: "\n"))\(extraSuffix)"
  }
}
