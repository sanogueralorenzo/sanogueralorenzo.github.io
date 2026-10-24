import CloudKit
import Foundation
import XCTest

@testable import Crest

final class BrowserCloudSyncStateTests: XCTestCase {
    func testCloudContainerEntitlementMustAuthorizeTheConfiguredContainer() {
        let identifier = "iCloud.com.pauldavis.crest"

        XCTAssertTrue(
            CloudKitBrowserCloudSyncRemoteService.containerEntitlement(
                [identifier, "iCloud.com.pauldavis.other"],
                contains: identifier
            )
        )
        XCTAssertFalse(
            CloudKitBrowserCloudSyncRemoteService.containerEntitlement(
                ["iCloud.com.pauldavis.other"],
                contains: identifier
            )
        )
        XCTAssertFalse(
            CloudKitBrowserCloudSyncRemoteService.containerEntitlement(
                nil,
                contains: identifier
            )
        )
    }

    /// Crest rebuilds a zone iCloud lost only when this device holds the
    /// surviving copy; a deletion or a purge is somebody's decision.
    func testRemovingCrestsICloudDataIsNotImmediatelyUndone() {
        XCTAssertFalse(BrowserCloudSyncEngine.loss(afterZoneDeletion: .purged).restoresLocalRecords)
        XCTAssertFalse(BrowserCloudSyncEngine.loss(afterZoneDeletion: .deleted).restoresLocalRecords)
        XCTAssertTrue(BrowserCloudSyncEngine.loss(afterZoneDeletion: .encryptedDataReset).restoresLocalRecords)
    }

    func testAFailedFetchEventReportsWhyRatherThanClaimingSuccess() {
        let service = CloudKitBrowserCloudSyncRemoteService(
            configuration: BrowserCloudSyncConfiguration(
                containerIdentifier: "iCloud.com.pauldavis.crest"
            )
        )

        XCTAssertEqual(
            service.message(for: BrowserCloudSyncError.remoteChangeNotApplied("boom")),
            "Crest couldn’t apply the latest changes from iCloud."
        )
    }

    /// The engine notes each merge with the core before it applies it, so a
    /// merge the core refuses leaves a full pull required for the next engine
    /// until a full snapshot is applied.
    @MainActor
    func testFailedMergeSurvivesRestartUntilAFullSnapshotIsApplied() async throws {
        let harness = try BrowserStoredSessionHarness(seed: .preview)
        await harness.store.flushPendingSyncPersistence()
        try harness.core.transport(
            OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: nil))
        // The core cannot save the merge's journal, so it refuses the merge.
        try harness.refuseWrites(to: "journal")
        let engine = try BrowserCloudSyncEngine(
            configuration: BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest"),
            core: harness.core, automaticallySync: false
        )
        do {
            try await engine.mergeDownloadedRecords([testSpaceRecord(index: 1)])
            XCTFail("Expected local persistence failure")
        } catch {}
        XCTAssertTrue(try harness.core.query(CloudTransport()).requiresFullPull)

        try harness.acceptWrites()
        let restarted = try BrowserCloudSyncEngine(
            configuration: BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest"),
            core: harness.core, automaticallySync: false
        )
        try await restarted.mergeDownloadedRecords([testSpaceRecord(index: 2)])
        XCTAssertTrue(try harness.core.query(CloudTransport()).requiresFullPull)
        try await restarted.mergeDownloadedRecords(
            [testSpaceRecord(index: 1), testSpaceRecord(index: 2)], isFullSnapshot: true)
        XCTAssertFalse(try harness.core.query(CloudTransport()).requiresFullPull)
    }

    /// A Space record as the cloud stores it.
    private func testSpaceRecord(index: Int) -> SyncRecord {
        let id = testUUID(prefix: 5, index: index)
        let value: [String: Any] = [
            "id": ["rawValue": id.uuidString], "profileID": testUUID(prefix: 6, index: index).uuidString,
            "name": "Space \(index)", "symbol": "square.grid.2x2.fill", "accent": "indigo", "orderToken": "a",
        ]
        let body = try! JSONSerialization.data(
            withJSONObject: ["type": "space", "value": value], options: [.sortedKeys])
        return SyncRecord(
            kind: .space, id: id, spaceID: id,
            version: SyncVersion(clock: UInt64(index), deviceID: testUUID(prefix: 7, index: 1)),
            schema: 1, body: body, isTombstone: false)
    }

    private func testUUID(prefix: Int, index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "%d0000000-0000-0000-0000-%012d",
                prefix,
                index
            )
        )!
    }
}
