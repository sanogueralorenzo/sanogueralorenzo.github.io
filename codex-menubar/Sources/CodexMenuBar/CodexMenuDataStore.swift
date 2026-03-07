import Foundation
import Observation

struct CodexMenuData {
    let isLoading: Bool
    let remoteStatus: CodexRemoteCLIClient.Status?
    let sessionsStatus: CodexSessionsCLIClient.Status?
    let currentProfileName: String?
    let profiles: [String]
    let installedSkills: [String]
    let limitsSnapshot: CodexRateLimitsSnapshot

    static let loading = CodexMenuData(
        isLoading: true,
        remoteStatus: nil,
        sessionsStatus: nil,
        currentProfileName: nil,
        profiles: [],
        installedSkills: [],
        limitsSnapshot: CodexRateLimitsSnapshot(
            entries: ["Loading..."],
            isMock: false,
            sourceNote: "Loading"
        )
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
                 sessionsCLI: CodexSessionsCLIClient,
                 skillsProvider: CodexSkillsProvider,
                 rateLimitsProvider: CodexRateLimitsProvider) {
        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let refreshedData = CodexMenuData(
                isLoading: false,
                remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
                sessionsStatus: (try? sessionsCLI.status()) ?? .notInstalled,
                currentProfileName: try? authCLI.currentProfileName(),
                profiles: (try? authCLI.listProfiles()) ?? [],
                installedSkills: skillsProvider.installedSkillNames(),
                limitsSnapshot: rateLimitsProvider.snapshot()
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
