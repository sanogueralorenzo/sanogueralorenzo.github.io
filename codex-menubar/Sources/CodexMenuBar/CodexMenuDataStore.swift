import Foundation
import Observation

struct CodexMenuData {
    let isLoading: Bool
    let remoteStatus: CodexRemoteCLIClient.Status?
    let sessionsStatus: CodexHubCLIClient.Status?
    let currentProfileName: String?
    let profiles: [String]

    static let loading = CodexMenuData(
        isLoading: true,
        remoteStatus: nil,
        sessionsStatus: nil,
        currentProfileName: nil,
        profiles: []
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
                 sessionsCLI: CodexHubCLIClient) {
        refreshGeneration += 1
        let generation = refreshGeneration
        let previousProfiles = data.profiles

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessionsStatus = (try? sessionsCLI.status()) ?? .notInstalled
            let profiles = (try? authCLI.listProfiles()) ?? previousProfiles

            let refreshedData = CodexMenuData(
                isLoading: false,
                remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
                sessionsStatus: sessionsStatus,
                currentProfileName: try? authCLI.currentProfileName(),
                profiles: profiles
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
