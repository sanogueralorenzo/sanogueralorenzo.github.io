import Foundation
import Observation

struct CodexMenuData {
  let isLoading: Bool
  let remoteStatus: CodexRemoteCLIClient.Status?
  let sessionsStatus: CodexCoreCLIClient.Status?
  let currentProfileName: String?
  let profiles: [String]
  let spikeJobs: [CodexCoreCLIClient.SpikeJob]
  let taskJobs: [CodexCoreCLIClient.TaskJob]
  let reviewJobs: [CodexCoreCLIClient.ReviewJob]

  static let loading = CodexMenuData(
    isLoading: true,
    remoteStatus: nil,
    sessionsStatus: nil,
    currentProfileName: nil,
    profiles: [],
    spikeJobs: [],
    taskJobs: [],
    reviewJobs: []
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
    let previousSpikeJobs = data.spikeJobs
    let previousTaskJobs = data.taskJobs
    let previousReviewJobs = data.reviewJobs

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let sessionsStatus = (try? sessionsCLI.status()) ?? .notInstalled
      let profiles = (try? authCLI.listProfiles()) ?? previousProfiles
      let spikeJobs: [CodexCoreCLIClient.SpikeJob]
      let taskJobs: [CodexCoreCLIClient.TaskJob]
      let reviewJobs: [CodexCoreCLIClient.ReviewJob]
      if sessionsStatus == .ready {
        spikeJobs = (try? sessionsCLI.listSpikeJobs()) ?? previousSpikeJobs
        taskJobs = (try? sessionsCLI.listTaskJobs()) ?? previousTaskJobs
        reviewJobs = (try? sessionsCLI.listReviewJobs()) ?? previousReviewJobs
      } else {
        spikeJobs = []
        taskJobs = []
        reviewJobs = []
      }

      let refreshedData = CodexMenuData(
        isLoading: false,
        remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
        sessionsStatus: sessionsStatus,
        currentProfileName: try? authCLI.currentProfileName(),
        profiles: profiles,
        spikeJobs: spikeJobs,
        taskJobs: taskJobs,
        reviewJobs: reviewJobs
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
