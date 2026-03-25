import Foundation
import Observation

struct CodexMenuData {
    let isLoading: Bool
    let remoteStatus: CodexRemoteCLIClient.Status?
    let sessionsStatus: CodexCoreCLIClient.Status?
    let currentProfileName: String?
    let profiles: [String]
    let reviewPullRequests: [CodexCoreCLIClient.ReviewPullRequest]

    static let loading = CodexMenuData(
        isLoading: true,
        remoteStatus: nil,
        sessionsStatus: nil,
        currentProfileName: nil,
        profiles: [],
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

    func refresh(authCLI: CodexAuthCLIClient,
                 remoteCLI: CodexRemoteCLIClient,
                 sessionsCLI: CodexCoreCLIClient) {
        refreshGeneration += 1
        let generation = refreshGeneration
        let previousProfiles = data.profiles
        let previousReviewPullRequests = data.reviewPullRequests

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessionsStatus = (try? sessionsCLI.status()) ?? .notInstalled
            let profiles = (try? authCLI.listProfiles()) ?? previousProfiles
            let reviewPullRequests: [CodexCoreCLIClient.ReviewPullRequest]
            if sessionsStatus == .ready {
                reviewPullRequests =
                    (try? sessionsCLI.listReviewPullRequests()) ?? previousReviewPullRequests
            } else {
                reviewPullRequests = []
            }

            let refreshedData = CodexMenuData(
                isLoading: false,
                remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
                sessionsStatus: sessionsStatus,
                currentProfileName: try? authCLI.currentProfileName(),
                profiles: profiles,
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
