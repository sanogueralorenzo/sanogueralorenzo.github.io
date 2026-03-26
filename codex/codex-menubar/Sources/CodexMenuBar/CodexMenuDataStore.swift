import Foundation
import Observation

struct CodexMenuData {
  let isLoading: Bool
  let remoteStatus: CodexRemoteCLIClient.Status?
  let sessionsStatus: CodexCoreCLIClient.Status?
  let currentProfileName: String?
  let profiles: [String]
  let taskJobs: [CodexCoreCLIClient.TaskJob]
  let taskCandidates: [CodexCoreCLIClient.TaskCandidate]
  let reviewJobs: [CodexCoreCLIClient.ReviewJob]
  let reviewPullRequests: [CodexCoreCLIClient.ReviewPullRequest]

  static let loading = CodexMenuData(
    isLoading: true,
    remoteStatus: nil,
    sessionsStatus: nil,
    currentProfileName: nil,
    profiles: [],
    taskJobs: [],
    taskCandidates: [],
    reviewJobs: [],
    reviewPullRequests: []
  )
}

@MainActor
@Observable
final class CodexMenuDataStore {
  private(set) var data: CodexMenuData = .loading
  private var refreshGeneration = 0

  func showLoading() {
    data = .loading
  }

  func refresh(
    authCLI: CodexAuthCLIClient,
    remoteCLI: CodexRemoteCLIClient,
    sessionsCLI: CodexCoreCLIClient
  ) {
    refreshGeneration += 1
    let generation = refreshGeneration
    let previousProfiles = data.profiles
    let previousTaskJobs = data.taskJobs
    let previousTaskCandidates = data.taskCandidates
    let previousReviewJobs = data.reviewJobs
    let previousReviewPullRequests = data.reviewPullRequests

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let sessionsStatus = (try? sessionsCLI.status()) ?? .notInstalled
      let profiles = (try? authCLI.listProfiles()) ?? previousProfiles
      let taskJobs: [CodexCoreCLIClient.TaskJob]
      let taskCandidates: [CodexCoreCLIClient.TaskCandidate]
      let reviewJobs: [CodexCoreCLIClient.ReviewJob]
      let reviewPullRequests: [CodexCoreCLIClient.ReviewPullRequest]
      if sessionsStatus == .ready {
        taskJobs = (try? sessionsCLI.listTaskJobs()) ?? previousTaskJobs
        taskCandidates = (try? sessionsCLI.listTaskCandidates()) ?? previousTaskCandidates
        reviewJobs = (try? sessionsCLI.listReviewJobs()) ?? previousReviewJobs
        reviewPullRequests =
          (try? sessionsCLI.listReviewPullRequests()) ?? previousReviewPullRequests
      } else {
        taskJobs = []
        taskCandidates = []
        reviewJobs = []
        reviewPullRequests = []
      }

      let refreshedData = CodexMenuData(
        isLoading: false,
        remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
        sessionsStatus: sessionsStatus,
        currentProfileName: try? authCLI.currentProfileName(),
        profiles: profiles,
        taskJobs: taskJobs,
        taskCandidates: taskCandidates,
        reviewJobs: reviewJobs,
        reviewPullRequests: reviewPullRequests
      )

      DispatchQueue.main.async {
        guard let self, generation == self.refreshGeneration else {
          return
        }
        self.data = refreshedData
      }
    }
  }
}
