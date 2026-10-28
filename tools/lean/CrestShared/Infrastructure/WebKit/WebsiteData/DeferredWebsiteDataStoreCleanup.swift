import Foundation
import WebKit

@MainActor
enum BrowserDeferredWebsiteDataStoreCleanup {
    private static let defaultsKey =
        "crest.browser.pending-empty-website-data-stores"
    private static var scheduledCleanup: Task<Void, Never>?

    static func record(_ identifier: UUID) {
        guard allowsPersistentMaintenance else { return }
        var identifiers = pendingIdentifiers
        identifiers.insert(identifier)
        persist(identifiers)
        scheduleCleanup()
    }

    static func markRemoved(_ identifier: UUID) {
        guard allowsPersistentMaintenance else { return }
        var identifiers = pendingIdentifiers
        guard identifiers.remove(identifier) != nil else { return }
        persist(identifiers)
    }

    static func cleanupPendingStores() async {
        guard allowsPersistentMaintenance else { return }
        let identifiers = pendingIdentifiers
        guard !identifiers.isEmpty else { return }

        for identifier in identifiers {
            let existingIdentifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
            guard existingIdentifiers.contains(identifier) else {
                markRemoved(identifier)
                continue
            }
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                markRemoved(identifier)
            } catch {
                // The store is already empty. Keep its identifier queued until
                // WebKit releases the last network-process reference.
            }
        }
    }

    private static var pendingIdentifiers: Set<UUID> {
        Set(
            UserDefaults.standard.stringArray(forKey: defaultsKey)?
                .compactMap(UUID.init(uuidString:)) ?? []
        )
    }

    private static var allowsPersistentMaintenance: Bool {
        !BrowserLaunchEnvironment.current.requiresIsolation
    }

    private static func persist(_ identifiers: Set<UUID>) {
        UserDefaults.standard.set(
            identifiers.map(\.uuidString).sorted(),
            forKey: defaultsKey
        )
    }

    private static func scheduleCleanup() {
        scheduledCleanup?.cancel()
        scheduledCleanup = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await cleanupPendingStores()
            scheduledCleanup = nil
        }
    }
}
