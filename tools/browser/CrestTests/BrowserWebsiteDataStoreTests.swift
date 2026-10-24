import XCTest

@testable import Crest

@MainActor
final class BrowserWebsiteDataStoreTests: XCTestCase {
    func testEphemeralProfileRemovalNeverOpensAPersistentWebKitStore() async throws {
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            identifierProvider: {
                XCTFail("Ephemeral profiles must not query persistent stores")
                return []
            },
            removeDataStore: { _ in XCTFail("Ephemeral profiles must not remove persistent stores") })
        try await remover.removeProfile(BrowsingProfile(), ephemeral: true)
    }

    /// A review that opens a copy of the installed session carries the
    /// installed profile IDs. The stores it opens and removes must never be the
    /// installed app's, and relaunching the same review finds its own again.
    func testNamedIsolatedLaunchNeverOpensOrRemovesTheInstalledProfileStores() async throws {
        let profile = BrowsingProfile()
        let installed = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
        let review = Self.namedIsolatedLaunch("review-a")
        let reviewStore = review.websiteDataStoreIdentifier(forProfileID: profile.id)

        XCTAssertEqual(installed.websiteDataStoreIdentifier(forProfileID: profile.id), profile.id)
        XCTAssertNotEqual(reviewStore, profile.id)
        XCTAssertEqual(
            Self.namedIsolatedLaunch("review-a").websiteDataStoreIdentifier(forProfileID: profile.id), reviewStore)
        XCTAssertNotEqual(
            Self.namedIsolatedLaunch("review-b").websiteDataStoreIdentifier(forProfileID: profile.id), reviewStore)
        XCTAssertNotEqual(review.websiteDataStoreIdentifier(forProfileID: BrowsingProfile().id), reviewStore)

        let installedStores = [profile.id, BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: profile.id)]
        var removed: [UUID] = []
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            identifierProvider: { installedStores + [reviewStore] },
            removeDataStore: { removed.append($0) },
            clearDataStore: { _ in XCTFail("No fallback should be needed") },
            completeCleanup: { _ in },
            storeIdentifier: { review.websiteDataStoreIdentifier(forProfileID: $0) })
        try await remover.removeProfile(profile, ephemeral: false)
        XCTAssertEqual(removed, [reviewStore])
    }

    func testSiteDataMatchingIncludesTheHostAndItsParentRecords() {
        XCTAssertTrue(
            BrowserWebsiteDataStore.matchesDataRecord(
                displayName: "localhost",
                host: "api.localhost"
            )
        )
        XCTAssertTrue(
            BrowserWebsiteDataStore.matchesDataRecord(
                displayName: "api.localhost",
                host: "api.localhost"
            )
        )
        XCTAssertFalse(
            BrowserWebsiteDataStore.matchesDataRecord(
                displayName: "notlocalhost.example",
                host: "localhost"
            )
        )
    }

    func testSiteCookieRemovalIncludesParentDomainsButNotUnrelatedSites() {
        XCTAssertTrue(BrowserWebsiteDataStore.includesCookieDomainForRemoval("localhost", host: "api.localhost"))
        XCTAssertTrue(
            BrowserWebsiteDataStore.includesCookieDomainForRemoval(
                ".localhost",
                host: "api.localhost"
            )
        )
        XCTAssertTrue(
            BrowserWebsiteDataStore.includesCookieDomainForRemoval(
                "api.localhost",
                host: "api.localhost"
            )
        )
        XCTAssertFalse(
            BrowserWebsiteDataStore.includesCookieDomainForRemoval(
                ".example.com",
                host: "api.localhost"
            )
        )
    }

    func testRemovingAProfileAlsoRemovesItsLegacyHostedExtensionStore() async throws {
        let profile = BrowsingProfile()
        let hostedID = BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: profile.id)
        var removed: [UUID] = []
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            identifierProvider: { [profile.id, hostedID] },
            removeDataStore: { removed.append($0) },
            clearDataStore: { _ in XCTFail("No fallback should be needed") })
        try await remover.removePersistentDataStore(for: profile)
        XCTAssertEqual(removed, [profile.id, hostedID])
        XCTAssertNotEqual(hostedID, profile.id)
    }

    func testRemovalRetriesTheFullDelayedReleaseSequenceBeforeSucceeding() async throws {
        let profile = BrowsingProfile()
        var removalAttempts = 0
        var observedDelays: [Duration] = []
        let expectedDelays: [Duration] = [
            .milliseconds(10),
            .milliseconds(20),
            .milliseconds(40),
        ]
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            retryDelays: expectedDelays,
            identifierProvider: { [profile] in [profile.id] },
            removeDataStore: { _ in
                removalAttempts += 1
                if removalAttempts <= expectedDelays.count {
                    throw TestWebsiteDataStoreRemovalError.storeInUse
                }
            },
            sleep: { delay in
                observedDelays.append(delay)
            },
            clearDataStore: { _ in },
            acceptsClearedStoreFallback: false
        )

        try await remover.removePersistentDataStore(for: profile)

        XCTAssertEqual(removalAttempts, expectedDelays.count + 1)
        XCTAssertEqual(observedDelays, expectedDelays)
    }

    func testClearedStoreCanFinishTransactionAndQueueContainerRemoval() async throws {
        let profile = BrowsingProfile()
        var clearedIdentifiers: [UUID] = []
        var deferredIdentifiers: [UUID] = []
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            retryDelays: [.milliseconds(10)],
            identifierProvider: { [profile] in [profile.id] },
            removeDataStore: { _ in
                throw TestWebsiteDataStoreRemovalError.storeInUse
            },
            sleep: { _ in },
            clearDataStore: { identifier in
                clearedIdentifiers.append(identifier)
            },
            recordDeferredCleanup: { identifier in
                deferredIdentifiers.append(identifier)
            }
        )

        try await remover.removePersistentDataStore(for: profile)

        XCTAssertEqual(clearedIdentifiers, [profile.id])
        XCTAssertEqual(deferredIdentifiers, [profile.id])
    }

    private static func namedIsolatedLaunch(_ isolationID: String) -> BrowserLaunchEnvironment {
        BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
    }
}

private enum TestWebsiteDataStoreRemovalError: Error, Equatable {
    case storeInUse
}
