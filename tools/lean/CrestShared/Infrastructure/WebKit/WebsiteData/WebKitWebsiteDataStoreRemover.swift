import Foundation
import WebKit

@MainActor
struct WebKitBrowserWebsiteDataStoreRemover: BrowserEngineProfileRemoving {
    typealias IdentifierProvider = @MainActor () async -> [UUID]
    typealias RemoveDataStore = @MainActor (UUID) async throws -> Void
    typealias Sleep = @MainActor (Duration) async throws -> Void
    typealias ClearDataStore = @MainActor (UUID) async throws -> Void
    typealias CleanupMarker = @MainActor (UUID) -> Void
    typealias StoreIdentifier = @MainActor (UUID) -> UUID

    static let defaultRetryDelays: [Duration] = [
        .milliseconds(125),
        .milliseconds(250),
        .milliseconds(500),
        .seconds(1),
        .seconds(2),
        .seconds(4),
    ]

    private let retryDelays: [Duration]
    private let identifierProvider: IdentifierProvider
    private let removeDataStore: RemoveDataStore
    private let sleep: Sleep
    private let clearDataStore: ClearDataStore
    private let recordDeferredCleanup: CleanupMarker
    private let completeCleanup: CleanupMarker
    private let storeIdentifier: StoreIdentifier
    private let acceptsClearedStoreFallback: Bool

    init(
        retryDelays: [Duration] = Self.defaultRetryDelays,
        identifierProvider: @escaping IdentifierProvider = {
            await WKWebsiteDataStore.allDataStoreIdentifiers
        },
        removeDataStore: @escaping RemoveDataStore = { identifier in
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        },
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        },
        clearDataStore: @escaping ClearDataStore = { identifier in
            try await Self.clearWebsiteData(for: identifier)
        },
        recordDeferredCleanup: @escaping CleanupMarker = { identifier in
            BrowserDeferredWebsiteDataStoreCleanup.record(identifier)
        },
        completeCleanup: @escaping CleanupMarker = { identifier in
            BrowserDeferredWebsiteDataStoreCleanup.markRemoved(identifier)
        },
        // Read when a profile is removed, not here: a review composition
        // names its isolation after its default remover already exists.
        storeIdentifier: @escaping StoreIdentifier = { profileID in
            BrowserLaunchEnvironment.current.websiteDataStoreIdentifier(forProfileID: profileID)
        },
        acceptsClearedStoreFallback: Bool = true
    ) {
        self.retryDelays = retryDelays
        self.identifierProvider = identifierProvider
        self.removeDataStore = removeDataStore
        self.sleep = sleep
        self.clearDataStore = clearDataStore
        self.recordDeferredCleanup = recordDeferredCleanup
        self.completeCleanup = completeCleanup
        self.storeIdentifier = storeIdentifier
        self.acceptsClearedStoreFallback = acceptsClearedStoreFallback
    }

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        guard !ephemeral else { return }
        try await removePersistentDataStore(for: profile)
    }

    /// Removes the stores this launch opens for `profile`, which in a named
    /// isolated launch are never the installed app's.
    func removePersistentDataStore(for profile: BrowsingProfile) async throws {
        let identifier = storeIdentifier(profile.id)
        try await removePersistentDataStore(identifier: identifier)
        try await removePersistentDataStore(
            identifier: BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: identifier))
    }

    private func removePersistentDataStore(identifier: UUID) async throws {
        var lastError: Error?
        var clearedWebsiteData = false

        for attempt in 0...retryDelays.count {
            let identifiers = await identifierProvider()
            guard identifiers.contains(identifier) else {
                completeCleanup(identifier)
                return
            }

            do {
                try await removeDataStore(identifier)
                completeCleanup(identifier)
                return
            } catch {
                if !clearedWebsiteData {
                    try await clearDataStore(identifier)
                    clearedWebsiteData = true
                }
                let remainingIdentifiers = await identifierProvider()
                guard remainingIdentifiers.contains(identifier) else {
                    completeCleanup(identifier)
                    return
                }
                lastError = error
                guard attempt < retryDelays.count else {
                    break
                }
                try await sleep(retryDelays[attempt])
            }
        }

        if clearedWebsiteData, acceptsClearedStoreFallback {
            recordDeferredCleanup(identifier)
            return
        }

        if let lastError {
            throw lastError
        }
    }

    private static func clearWebsiteData(for identifier: UUID) async throws {
        let dataStore = WKWebsiteDataStore(forIdentifier: identifier)
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }
}
