import XCTest

@testable import Crest

@MainActor
final class BrowserWebsiteDataStoreTests: XCTestCase {
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

    private static func namedIsolatedLaunch(_ isolationID: String) -> BrowserLaunchEnvironment {
        BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
    }
}
