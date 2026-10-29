import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativeWebsiteDataTests: XCTestCase {
    func testListingsMatchCapturedCrestAnswersIncludingOrdinalNamesAndHostFiltering() throws {
        struct Site: Decodable {
            let site: String
            let kinds: [String]
            var value: StoredSite { StoredSite(site: site, kinds: kinds.compactMap(WebsiteDataKind.init(rawValue:))) }
        }
        struct Row: Decodable {
            let host: String?
            let invalid: Bool
            let sites: [Site]
            let expected: [Site]
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/website-data-crest-baseline.json")
        let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            if row.invalid {
                XCTAssertThrowsError(try NativeWebsiteData.normalize(row.sites.map(\.value), host: row.host)) {
                    XCTAssertEqual($0 as? WebsiteDataFailure, .invalidSiteHost)
                }
            } else {
                let answer = try NativeWebsiteData.normalize(row.sites.map(\.value), host: row.host)
                XCTAssertEqual(answer.map { Data($0.site.utf8) }, row.expected.map { Data($0.site.utf8) })
                XCTAssertEqual(answer.map { $0.kinds.map(\.name) }, row.expected.map(\.kinds))
            }
        }
    }

    func testClearingValidatesHostsAndKeepsOnlyTheSupportedCategories() throws {
        let profile = UUID()
        let request = DeleteSiteData(
            profileID: profile, ephemeral: true,
            hosts: [" Example.COM ", "example.com", "other.example"], categories: [.cache, .history, .siteData, .cache])
        let validated = try request.validated()
        XCTAssertEqual(validated.hosts, ["example.com", "other.example"])
        XCTAssertEqual(validated.categories, [.siteData, .cache])
        XCTAssertEqual(validated.profileID, profile)
        XCTAssertTrue(validated.ephemeral)
        for hosts in [[], [" "], [String(repeating: "x", count: 254)]] {
            XCTAssertThrowsError(
                try DeleteSiteData(
                    profileID: profile, ephemeral: false, hosts: hosts, categories: [.cache]
                ).validated()
            ) {
                XCTAssertEqual($0 as? WebsiteDataFailure, .invalidSiteHost)
            }
        }
        XCTAssertThrowsError(
            try DeleteSiteData(
                profileID: profile, ephemeral: false, hosts: ["example.com"], categories: [.history]
            ).validated()
        ) {
            XCTAssertEqual($0 as? WebsiteDataFailure, .noCategory)
        }
        XCTAssertThrowsError(
            try DeleteBrowsingData(
                profileID: profile, ephemeral: false, range: .allTime, categories: []
            ).validated())
        let all = try DeleteBrowsingData(
            profileID: profile, ephemeral: false, range: .allTime,
            categories: [.cache, .history, .siteData, .history]
        ).validated()
        XCTAssertEqual(all.categories, BrowsingDataCategory.all)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for (range, seconds): (BrowsingDataRange, Double) in [
            (.lastHour, 3_600), (.lastDay, 86_400), (.lastWeek, 604_800), (.lastFourWeeks, 2_419_200),
        ] {
            XCTAssertEqual(range.since(now), now.addingTimeInterval(-seconds))
        }
        XCTAssertNil(BrowsingDataRange.allTime.since(now))
    }

    func testSpaceRemovalWaitsForSuccessfulErasureAndQuitIsBlockedOnlyWhileItRuns() async throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let stores = SuspendedStores()
        register(stores, in: harness.core)
        let space = try XCTUnwrap(harness.store.spaceModels.first)
        let operation = UUID()
        try begin(space.id, operation, in: harness.store)
        let finish = FinishDeletingSpace(
            workspaceID: harness.store.family.workspaceID, windowID: harness.store.windowID,
            spaceID: space.id, operationID: operation)
        assertUnproved(finish, in: harness.core)
        let failed = Task { await harness.core.deleteData(self.erase(space.profileID)) }
        try await stores.waitFor(1)
        XCTAssertEqual(harness.core.websiteData.quitBarriers, [space.id])
        XCTAssertThrowsError(try harness.core.closing.allPagesForQuit()) {
            guard case .spaceDeletionUnderway(let barrier) = $0 as? NativeClosePreparation.Failure else {
                return XCTFail("Unexpected refusal: \($0)")
            }
            XCTAssertEqual(barrier.spaceIDs, [space.id])
        }
        stores.finish(0, success: false)
        let failure = await failed.value
        XCTAssertFalse(failure)
        XCTAssertTrue(harness.core.websiteData.quitBarriers.isEmpty)
        assertUnproved(finish, in: harness.core)
        let retry = Task { await harness.core.deleteData(self.erase(space.profileID)) }
        try await stores.waitFor(2)
        stores.finish(1, success: true)
        let success = await retry.value
        XCTAssertTrue(success)
        XCTAssertTrue(harness.core.websiteData.hasErased(space.profileID))
        try sendGenerically(finish, to: harness.core)
        XCTAssertNil(harness.store.spaceModel(space.id))
    }

    func testRestartKeepsThePendingOperationButRequiresFreshErasureProof() async throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let space = try XCTUnwrap(harness.store.spaceModels.first)
        let operation = UUID()
        try begin(space.id, operation, in: harness.store)
        let first = await harness.core.deleteData(erase(space.profileID))
        XCTAssertTrue(first)
        XCTAssertTrue(harness.core.websiteData.hasErased(space.profileID))
        let restarted = try await harness.relaunch()
        let finish = FinishDeletingSpace(
            workspaceID: restarted.store.family.workspaceID, windowID: restarted.store.windowID,
            spaceID: space.id, operationID: operation)
        assertUnproved(finish, in: restarted.core)
        let again = await restarted.core.deleteData(erase(space.profileID))
        XCTAssertTrue(again)
        try sendGenerically(finish, to: restarted.core)
        XCTAssertNil(restarted.store.spaceModel(space.id))
    }

    func testOverlappingErasureCannotTurnAnOlderSuccessIntoNewerProof() async throws {
        let stores = SuspendedStores()
        let core = CrestCore.hostingPages(profileStores: stores)
        let profile = UUID()
        let request = erase(profile)
        let first = Task { await core.deleteData(request) }
        try await stores.waitFor(1)
        let second = Task { await core.deleteData(request) }
        try await stores.waitFor(2)
        stores.finish(1, success: false)
        let newer = await second.value
        XCTAssertFalse(newer)
        XCTAssertTrue(core.websiteData.isErasing(profile))
        stores.finish(0, success: true)
        let older = await first.value
        XCTAssertTrue(older)
        XCTAssertFalse(core.websiteData.isErasing(profile))
        XCTAssertFalse(core.websiteData.hasErased(profile))
    }

    func testCancelingTheCallerDoesNotAbandonStartedErasure() async throws {
        let stores = SuspendedStores()
        let core = CrestCore.hostingPages(profileStores: stores)
        let profile = UUID()
        let task = Task { await core.deleteData(self.erase(profile)) }
        try await stores.waitFor(1)
        task.cancel()
        stores.finish(0, success: true)
        let success = await task.value
        XCTAssertTrue(success)
        XCTAssertTrue(core.websiteData.hasErased(profile))
        XCTAssertEqual(stores.canceled, [false])
    }

    func testIdleReadsAndPartialClearsDoNotCreateStoresOrGrantProfileProof() async throws {
        let core = CrestCore.hostingPages()
        let profile = UUID()
        let result = await core.readWebsiteData(
            ReadWebsiteData(
                profileID: profile, ephemeral: true, host: "EXAMPLE.COM"))
        XCTAssertEqual(result, WebsiteDataRead(sites: [], complete: true))
        let invalid = await core.readWebsiteData(
            ReadWebsiteData(
                profileID: profile, ephemeral: true, host: " . "))
        XCTAssertNil(invalid)
        let browsing = await core.deleteData(
            DeleteBrowsingData(
                profileID: profile, ephemeral: true, range: .allTime, categories: [.siteData, .cache]))
        let site = await core.deleteData(
            DeleteSiteData(
                profileID: profile, ephemeral: true, hosts: ["example.com"], categories: [.siteData]))
        XCTAssertTrue(browsing)
        XCTAssertTrue(site)
        XCTAssertFalse(core.websiteData.hasErased(profile))
        XCTAssertTrue(try XCTUnwrap(core.engines.webKit).memoryStores.isEmpty)
    }

    private func seed() -> SessionState.Seed {
        SessionState.Seed(spaces: [
            SpaceState.Seed(name: "Work", tabs: []), SpaceState.Seed(name: "Personal", tabs: []),
        ])
    }
    private func register(_ stores: SuspendedStores, in core: CrestCore) {
        core.engines.register(
            WebKitEngineBinding(
                profileStores: stores, keepsProfilesInMemory: true, contentBlocking: WebKitContentBlocking()))
    }
    private func erase(_ profile: UUID) -> DeleteProfileData {
        DeleteProfileData(profileID: profile, ephemeral: false)
    }
    private func begin(_ space: UUID, _ operation: UUID, in browser: BrowserStore) throws {
        try browser.core.send(
            BeginDeletingSpace(
                workspaceID: browser.family.workspaceID, windowID: browser.windowID, spaceID: space,
                operationID: operation))
    }
    private func sendGenerically(_ intent: some SessionIntent, to core: CrestCore) throws { try core.send(intent) }
    private func assertUnproved(_ finish: FinishDeletingSpace, in core: CrestCore) {
        XCTAssertThrowsError(try sendGenerically(finish, to: core)) {
            XCTAssertEqual($0 as? Rejection, .spaceDataNotErased(SpaceDataNotErased(spaceID: finish.spaceID)))
        }
    }
}

@MainActor
private final class SuspendedStores: BrowserEngineProfileRemoving {
    private var pending: [CheckedContinuation<Void, any Error>?] = []
    private(set) var canceled: [Bool] = []
    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        try await withCheckedThrowingContinuation { pending.append($0) }
        canceled.append(Task.isCancelled)
        try Task.checkCancellation()
    }
    func finish(_ index: Int, success: Bool) {
        let continuation = pending[index]
        pending[index] = nil
        if success { continuation?.resume() } else { continuation?.resume(throwing: CancellationError()) }
    }
    func waitFor(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pending.count < count && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        _ = try XCTUnwrap(pending.count >= count ? true : nil, "Erasure did not reach the profile store")
    }
}
