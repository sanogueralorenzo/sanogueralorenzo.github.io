import Foundation
import Observation

struct CodexMenuData {
    let isLoading: Bool
    let remoteStatus: CodexRemoteCLIClient.Status?
    let sessionsStatus: CodexSessionsCLIClient.Status?
    let isSessionTitleWatcherRunning: Bool
    let currentProfileName: String?
    let profiles: [String]
    let installedSkills: [String]

    static let loading = CodexMenuData(
        isLoading: true,
        remoteStatus: nil,
        sessionsStatus: nil,
        isSessionTitleWatcherRunning: false,
        currentProfileName: nil,
        profiles: [],
        installedSkills: []
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
                 skillsProvider: CodexSkillsProvider) {
        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sessionsStatus = (try? sessionsCLI.status()) ?? .notInstalled
            let isSessionTitleWatcherRunning: Bool
            switch sessionsStatus {
            case .notInstalled:
                isSessionTitleWatcherRunning = false
            case .ready:
                isSessionTitleWatcherRunning = (try? sessionsCLI.isTitleWatcherRunning()) ?? false
            }

            let refreshedData = CodexMenuData(
                isLoading: false,
                remoteStatus: (try? remoteCLI.status()) ?? .notInstalled,
                sessionsStatus: sessionsStatus,
                isSessionTitleWatcherRunning: isSessionTitleWatcherRunning,
                currentProfileName: try? authCLI.currentProfileName(),
                profiles: (try? authCLI.listProfiles()) ?? [],
                installedSkills: skillsProvider.installedSkillNames()
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
