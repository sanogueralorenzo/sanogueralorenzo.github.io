import Foundation
import Observation

// MARK: - Types

enum BrowserGitHubFailure: Error, Equatable {
    case notSignedIn
    case unavailable
    case noFilters
    case invalidResponse
}

/// Transient authenticated results for one Space. The core owns the live
/// folder and tabs; retired sessions cannot publish new collection data.
@MainActor
@Observable
final class BrowserGitHubIntegration {
    // MARK: - Variables

    private(set) var items: [BrowserGitHubPullRequest] = []
    private(set) var failure: BrowserGitHubFailure?
    private(set) var isLoading = false
    private(set) var hasRefreshed = false
    private(set) var repositories: [String] = []
    private(set) var lastFetched: Date?
    var folderID: UUID?
    private(set) var refreshGeneration = 0
    private(set) var connectionGeneration = 0
    @ObservationIgnored private var generation = UUID()

    // MARK: - Actions - Refreshing

    func requestRefresh() {
        refreshGeneration &+= 1
    }

    func requestConnection() { connectionGeneration &+= 1 }

    func retireRefresh() {
        generation = UUID()
        isLoading = false
    }

    func reset() {
        generation = UUID()
        items = []
        failure = nil
        isLoading = false
        hasRefreshed = false
        repositories = []
        lastFetched = nil
    }

    func refresh(
        fetch: @MainActor () async throws -> [BrowserGitHubPullRequest], isCurrent: @MainActor () -> Bool
    ) async {
        guard !isLoading, !Task.isCancelled, isCurrent() else { return }
        let request = generation
        isLoading = true
        defer {
            if generation == request {
                isLoading = false
                if !Task.isCancelled, isCurrent() { lastFetched = Date() }
            }
        }
        do {
            let fetched = try await fetch()
            guard generation == request, !Task.isCancelled, isCurrent() else { return }
            items = fetched
            repositories = Array(Set(fetched.map(\.repository))).sorted()
            failure = nil
            hasRefreshed = true
        } catch {
            guard generation == request, !Task.isCancelled, isCurrent() else { return }
            failure = error as? BrowserGitHubFailure ?? .unavailable
            if failure == .notSignedIn {
                items = []
                repositories = []
            }
        }
    }
}
