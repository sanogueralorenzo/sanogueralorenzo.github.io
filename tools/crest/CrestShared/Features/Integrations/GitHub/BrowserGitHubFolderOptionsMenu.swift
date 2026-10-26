import SwiftUI

/// Zen's complete GitHub options, persisted by the owning folder's core intent.
struct BrowserGitHubFolderOptionsMenu: View {
    // MARK: - Variables

    let configuration: BrowserFolderGroupConfiguration
    @Environment(BrowserGitHubIntegration.self) private var github: BrowserGitHubIntegration?

    private var folder: FolderStateModel { configuration.folder }
    private var options: GitHubLiveFolderOptions { folder.gitHubOptions }
    private var repositories: [String] {
        let names = (github?.repositories ?? []) + options.excludedRepositories
        return Array(names.reduce(into: [String: String]()) { $0[$1.lowercased()] = $1 }.values)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        Menu("Live Folder Options") {
            status.disabled(true)
            Picker("Fetch Interval", selection: binding(\.interval)) {
                ForEach(LiveFolderRefreshInterval.all, id: \.self) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            Button("Refresh", systemImage: "arrow.clockwise") { github?.requestRefresh() }
                .disabled(github?.isLoading == true)
            Divider()
            Toggle("Created by Me", isOn: binding(\.authorMe))
            Toggle("Assigned to Me", isOn: binding(\.assignedMe))
            Toggle("Review Requests", isOn: binding(\.reviewRequested))
            Toggle("Include Draft Pull Requests", isOn: binding(\.includeDrafts))
            Divider()
            Menu("Repositories") {
                ForEach(repositories, id: \.self) { repository in
                    Toggle(
                        isOn: Binding(
                            get: {
                                !options.excludedRepositories.contains {
                                    $0.caseInsensitiveCompare(repository) == .orderedSame
                                }
                            },
                            set: { included in
                                var next = options
                                next.excludedRepositories.removeAll {
                                    $0.caseInsensitiveCompare(repository) == .orderedSame
                                }
                                if !included { next.excludedRepositories.append(repository) }
                                apply(next)
                            })
                    ) { Text(verbatim: repository) }
                }
                Divider()
                Text("This list is generated based on your currently active pull requests.").disabled(true)
            }.disabled(repositories.isEmpty)
        }
        .disabled(!configuration.isCurrentAndAvailable)
    }

    @ViewBuilder
    private var status: some View {
        if github?.failure == .notSignedIn {
            Text("Not signed in to GitHub")
        } else if github?.failure == .noFilters {
            Text("Filter is not set")
        } else if github?.failure != nil {
            Text("Failed to update")
        } else if let date = github?.lastFetched {
            Text("Last fetch: \(date.formatted(.relative(presentation: .numeric)))")
        } else {
            Text("Not fetched yet")
        }
    }

    // MARK: - Actions - Editing

    private func binding<Value>(_ key: WritableKeyPath<GitHubLiveFolderOptions, Value>) -> Binding<Value> {
        Binding(
            get: { options[keyPath: key] },
            set: { value in
                var next = options
                next[keyPath: key] = value
                apply(next)
            })
    }

    private func apply(_ options: GitHubLiveFolderOptions) {
        guard configuration.isCurrentAndAvailable, !configuration.browser.isPrivateBrowsing,
            let space = configuration.browser.selectedAvailableSpace(
                matching: configuration.assignment),
            space.folders.model(folder.id)?.source == .gitHubPullRequests
        else { return }
        let change = SetGitHubLiveFolderOptions(
            workspaceID: configuration.browser.family.workspaceID, spaceID: configuration.spaceID,
            profileID: configuration.profileID, folderID: folder.id, options: options)
        _ = configuration.browser.family.send(change, from: configuration.browser)
    }
}
