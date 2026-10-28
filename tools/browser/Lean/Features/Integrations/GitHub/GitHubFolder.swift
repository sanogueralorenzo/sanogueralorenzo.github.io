import Foundation
import Observation
import WebKit

/// One collector per Space, using its cookie store even when every GitHub tab sleeps.
@MainActor
@Observable
final class GitHubFolder: NSObject, WKHTTPCookieStoreObserver {
    let spaceID: UUID
    private(set) var items: [BrowserGitHubPullRequest] = []
    private(set) var lastFetched: Date?
    private(set) var repositories: [String] = []
    private(set) var isSignedIn = false
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private weak var store: BrowserStore?
    @ObservationIgnored private let cookies: WKHTTPCookieStore
    @ObservationIgnored private let session: WebKitIntegrationSession
    @ObservationIgnored private let client = BrowserGitHubClient()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var retired = false

    init(spaceID: UUID, store: BrowserStore) {
        self.spaceID = spaceID
        self.store = store
        let profile = store.profile(for: spaceID)
        cookies = profile.httpCookieStore
        session = WebKitIntegrationSession(store: profile, origin: URL(string: "https://github.com")!) {
            [weak store] in store?.session.spaces.contains { $0.id == spaceID } == true
        }
        super.init()
    }

    func start() {
        cookies.add(self)
        requestRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let store = self.store else { return }
                let interval =
                    store.session.spaces.first { $0.id == self.spaceID }?.folders.first { $0.kind == .github }?
                    .githubOptions.intervalMinutes ?? 30
                if self.lastFetched.map({ Date().timeIntervalSince($0) >= Double(interval * 60) }) ?? true {
                    self.requestRefresh()
                }
            }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { requestRefresh() }

    func requestRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func invalidate() {
        retired = true
        timer?.invalidate()
        refreshTask?.cancel()
        cookies.remove(self)
        session.invalidate()
    }

    private func refresh() async {
        guard !retired, let store,
            store.session.spaces.first(where: { $0.id == spaceID })?.isPrivate == false
        else { return }
        let values = await cookies.allCookies()
        guard !retired, !Task.isCancelled else { return }
        isSignedIn = values.contains {
            ($0.domain == "github.com" || $0.domain == ".github.com") && $0.name == "logged_in" && $0.value == "yes"
        }
        guard isSignedIn else {
            items = []
            error = nil
            isLoading = false
            return
        }
        guard let space = store.session.spaces.first(where: { $0.id == spaceID }) else { return }
        var folder = space.folders.first { $0.kind == .github }
        if folder == nil, !space.githubDismissed {
            do {
                let id = try store.owner.addFolder(github: true, in: spaceID)
                folder = store.session.spaces.first { $0.id == self.spaceID }?.folders.first { $0.id == id }
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
        guard let folder else { return }
        guard folder.githubOptions.hasFilters else {
            items = []
            error = nil
            isLoading = false
            return
        }
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await client.read(from: session, options: folder.githubOptions)
            guard !retired, !Task.isCancelled,
                let latest = store.session.spaces.first(where: { $0.id == spaceID }),
                latest.folders.contains(where: { $0.id == folder.id && $0.githubOptions == folder.githubOptions })
            else { return }
            guard await store.reconcileGitHub(result, folderID: folder.id, in: spaceID, options: folder.githubOptions)
            else {
                error = "Couldn’t update the GitHub folder."
                return
            }
            items = result
            repositories = Array(Set(result.map(\.repository) + folder.githubOptions.excludedRepositories)).sorted()
            lastFetched = Date()
            error = nil
        } catch is CancellationError {
        } catch BrowserGitHubFailure.notSignedIn {
            items = []
            isSignedIn = false
            self.error = nil
        } catch {
            guard !retired, !Task.isCancelled else { return }
            self.error = "Couldn’t refresh GitHub"
        }
    }
}
