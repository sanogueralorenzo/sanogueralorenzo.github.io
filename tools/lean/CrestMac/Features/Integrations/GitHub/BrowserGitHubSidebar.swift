import SwiftUI

/// Binds the profile's background session to real saved tabs. It neither owns
/// nor keeps a GitHub page resident; ordinary folder and tab views draw results.
struct BrowserGitHubSidebar: View {
    // MARK: - Types

    private struct SessionIdentity: Equatable {
        let assignment: BrowserSpaceRuntimeAssignment
        let folderID: UUID?
        let isAllowed: Bool
        let engines: EnginePreferences
    }

    private struct RefreshIdentity: Equatable {
        let session: ObjectIdentifier?
        let revision: Int?
        let options: GitHubLiveFolderOptions
        let manualGeneration: Int
    }

    // MARK: - Variables

    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool
    let integration: BrowserGitHubIntegration

    @Environment(\.sidebarSpaceIsSelected) private var isSelected
    @State private var session: (any BrowserIntegrationSession)?
    @State private var client = BrowserGitHubClient()
    @State private var lastAttempt: RefreshIdentity?

    private var assignment: BrowserSpaceRuntimeAssignment { BrowserSpaceRuntimeAssignment(space: space) }
    private var folder: FolderStateModel? { space.folders.models.first { $0.source == .gitHubPullRequests } }
    private var isAllowed: Bool {
        isSelected == true && !browser.isPrivateBrowsing
            && !space.settings.isGitHubFolderDismissed
            && browser.selectedAvailableSpace(matching: assignment) != nil
    }
    private var sessionIdentity: SessionIdentity {
        SessionIdentity(
            assignment: assignment, folderID: folder?.id, isAllowed: isAllowed,
            engines: browser.core.state.enginePreferences)
    }
    private var refreshIdentity: RefreshIdentity {
        RefreshIdentity(
            session: session.map(ObjectIdentifier.init), revision: session?.revision,
            options: folder?.gitHubOptions ?? .default, manualGeneration: integration.refreshGeneration)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: sessionIdentity, initial: true) { _, _ in replaceSession() }
            .onDisappear {
                session?.invalidate()
                session = nil
                integration.reset()
            }
            .task(id: refreshIdentity) {
                integration.retireRefresh()
                guard let session, isAllowed else { return }
                let identity = refreshIdentity
                let canWait =
                    lastAttempt.map {
                        $0.session == identity.session && $0.revision == identity.revision
                            && $0.manualGeneration == identity.manualGeneration
                            && $0.options.matchesFilters(identity.options)
                    } ?? false
                if canWait, let lastFetched = integration.lastFetched {
                    let remaining = lastFetched.addingTimeInterval(Double(identity.options.interval.minutes * 60))
                        .timeIntervalSinceNow
                    if remaining > 0 { do { try await Task.sleep(for: .seconds(remaining)) } catch { return } }
                }
                while !Task.isCancelled {
                    await refresh(using: session)
                    guard !Task.isCancelled, refreshIdentity == identity else { return }
                    lastAttempt = identity
                    do { try await Task.sleep(for: .seconds(identity.options.interval.minutes * 60)) } catch { return }
                }
            }
            .onChange(of: integration.connectionGeneration) { _, _ in
                if isAllowed { openSource() }
            }
    }

    // MARK: - Actions - Session

    private func replaceSession() {
        session?.invalidate()
        session = nil
        integration.reset()
        lastAttempt = nil
        client.reset()
        integration.folderID = folder?.id
        guard isAllowed, let origin = URL(string: "https://github.com") else { return }
        let assignment = assignment
        session = browser.core.engines.makeIntegrationSession(
            profileID: assignment.profileID, origin: origin,
            isAuthorized: { [weak browser] in
                guard let browser, !browser.isPrivateBrowsing,
                    let space = browser.selectedAvailableSpace(matching: assignment)
                else { return false }
                return !space.settings.isGitHubFolderDismissed
            })
    }

    private func refresh(using source: any BrowserIntegrationSession) async {
        let identity = refreshIdentity
        guard isAllowed, session === source else { return }
        await integration.refresh(
            fetch: { try await client.read(from: source, options: identity.options) },
            isCurrent: { isAllowed && session === source && refreshIdentity == identity })
        guard !Task.isCancelled, isAllowed, session === source, refreshIdentity == identity,
            integration.failure == nil, integration.hasRefreshed
        else { return }
        let refresh = RefreshLiveFolder(
            workspaceID: browser.family.workspaceID, spaceID: assignment.spaceID, profileID: assignment.profileID,
            folderID: folder?.id ?? UUID(), source: .gitHubPullRequests,
            tabs: integration.items.map { LiveFolderTab(url: $0.url.absoluteString, title: $0.title) },
            expectedOptions: identity.options)
        if browser.family.send(refresh, from: browser) { pages.reconcile() }
    }

    // MARK: - Actions - Navigation

    private func openSource() {
        guard isAllowed else { return }
        if let tab = space.tabs.models.first(where: { BrowserGitHubPullRequest.accepts($0.address) }) {
            browser.selectTab(tab.id)
        } else if let url = URL(string: "https://github.com/pulls") {
            browser.openNewTab(url: url, matching: assignment)
        }
        pages.select()
    }
}
