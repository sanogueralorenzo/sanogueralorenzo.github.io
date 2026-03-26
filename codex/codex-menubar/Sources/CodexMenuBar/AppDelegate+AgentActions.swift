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
                    let postedLabel = result.publishMode == .pending ? "Pending findings" : "Posted comments"
                    let failureDetails = result.failedCommentDetails.prefix(5).map { detail in
                        let path = detail.path ?? "<unknown>"
                        return "- \(detail.title) (\(path):\(detail.startLine)-\(detail.endLine)): \(detail.reason)"
                    }
                    let failureText: String
                    if failureDetails.isEmpty {
                        failureText = ""
                    } else {
                        let extraCount = result.failedCommentDetails.count - failureDetails.count
                        let extraSuffix = extraCount > 0 ? "\n- ... and \(extraCount) more" : ""
                        failureText = "\nFailure reasons:\n\(failureDetails.joined(separator: "\n"))\(extraSuffix)"
                    }
                    self.showMessage(
                        title: "Review Complete",
                        message: """
                        Review ID: \(result.reviewId)
                        Review mode: \(result.publishMode.rawValue)
                        PR: \(result.repo)#\(result.number)
                        \(postedLabel): \(result.postedComments)
                        Failed comments: \(result.failedComments)
                        Summary: \(result.summary)\(failureText)
                        """
                    )
                    self.refreshUI()
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error)
                }
            }
        }
    }

    @objc func openReviewRepository(_ sender: NSMenuItem) {
        guard let repositoryURL = sender.representedObject as? String,
              let url = URL(string: repositoryURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func viewCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will open real task details when agent backend is integrated.
    }

    @objc func togglePauseCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will pause/resume the selected running task.
    }

    @objc func deleteCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will delete/stop the selected task.
    }

    @objc func rerunCodexAgentTask(_ sender: NSMenuItem) {
        // MOCK placeholder: this will re-queue the selected completed task.
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
            } catch {
                guard codexAgentSettingsWindowController === controller else {
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                controller.applyLoadError(message)
            }
        }
    }
}
