import CloudKit
import Foundation
import XCTest

@testable import Crest

/// How the transport maps the core's synced records to CloudKit records: the
/// envelope's fields and types, the owning Space's reference, zone isolation,
/// the server's system fields, and the payload or tombstone bytes the core
/// spelled, copied as they are. What a payload holds is the core's codec's.
final class BrowserCloudRecordCodecTests: XCTestCase {
    func testRecordsMapToCloudKitFieldsAndBackWithTheirBytes() throws {
        let codec = BrowserCloudRecordCodec()
        for source in [makeTabRecord(), makeTombstone(), makeSpaceRecord()] {
            let cloud = try codec.record(for: source)

            XCTAssertEqual(cloud.recordType, source.kind.cloudRecordType)
            XCTAssertEqual(cloud.recordID.recordName, "\(source.kind.name):\(source.id.uuidString.lowercased())")
            XCTAssertEqual((cloud["schemaVersion"] as? NSNumber)?.intValue, source.schema)
            XCTAssertEqual(cloud["spaceID"] as? String, source.spaceID.uuidString.lowercased())
            XCTAssertEqual((cloud["logicalClock"] as? NSNumber)?.uint64Value, source.version.clock)
            XCTAssertEqual(cloud["deviceID"] as? String, source.version.deviceID.uuidString.lowercased())
            XCTAssertEqual(cloud.encryptedValues[source.isTombstone ? "tombstone" : "payload"] as? Data, source.body)
            XCTAssertNil(cloud.encryptedValues[source.isTombstone ? "payload" : "tombstone"] as? Data)
            XCTAssertNil(cloud["payload"])
            XCTAssertEqual(codec.syncRecord(from: cloud), source)
        }
    }

    func testReviewZonesCannotReadOrReuseProductionRecords() throws {
        let source = makeTabRecord()
        let production = BrowserCloudRecordCodec()
        let review = BrowserCloudRecordCodec(zoneName: "CrestReview-test")
        let record = try review.record(for: source)
        XCTAssertEqual(record.recordID.zoneID, review.recordZoneID)
        XCTAssertEqual((record["space"] as? CKRecord.Reference)?.recordID.zoneID, review.recordZoneID)
        XCTAssertEqual(review.syncRecord(from: record), source)
        XCTAssertNil(production.syncRecord(from: record))
        let liveRecord = try production.record(for: source)
        XCTAssertNil(review.syncRecord(from: liveRecord))
        XCTAssertThrowsError(try review.record(for: source, reusing: liveRecord))
    }

    /// A record that is not one of Crest's is nobody's to read: another zone,
    /// a type its name does not match, a missing schema, clock or identity, or
    /// both or neither of a payload and a tombstone.
    func testEnvelopesThatAreNotCrestsReadAsNothing() throws {
        let source = makeTabRecord()
        let codec = BrowserCloudRecordCodec()
        let wrongZone = CKRecord(
            recordType: "CrestTab",
            recordID: CKRecord.ID(
                recordName: "tab:\(source.id.uuidString.lowercased())", zoneID: .init(zoneName: "Other")))
        XCTAssertNil(codec.syncRecord(from: wrongZone))
        let good = try codec.record(for: source)
        XCTAssertNil(codec.syncRecord(from: CKRecord(recordType: "CrestFolder", recordID: good.recordID)))
        for field in ["schemaVersion", "spaceID", "logicalClock", "deviceID"] {
            let missing = try codec.record(for: source)
            missing[field] = nil
            XCTAssertNil(codec.syncRecord(from: missing), field)
        }
        let both = try codec.record(for: source)
        both.encryptedValues["tombstone"] = Data("{}".utf8) as CKRecordValue
        XCTAssertNil(codec.syncRecord(from: both))
        let neither = try codec.record(for: source)
        neither.encryptedValues["payload"] = nil
        XCTAssertNil(codec.syncRecord(from: neither))
    }

    @MainActor
    func testNewerServerSchemaCannotBeOverwrittenUsingRestoredSystemFields() throws {
        let source = makeTabRecord()
        let server = try BrowserCloudRecordCodec().record(for: source)
        server["schemaVersion"] = NSNumber(value: 99)
        // The schema is kept beside the archived fields in the core's device
        // store, since the archive leaves it out.
        let core = CrestCore()
        try core.transport(OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: nil))
        try core.transport(RecordCloudFields(updated: [CloudRecordFields(record: server)], removed: []))
        let kept = try core.query(CloudFieldsOf(recordNames: [server.recordID.recordName])).records
        let base = try XCTUnwrap(kept.first?.record(for: server.recordID))
        XCTAssertThrowsError(try BrowserCloudRecordCodec().record(for: source, reusing: base)) { error in
            XCTAssertEqual(error as? BrowserCloudRecordCodecError, .newerSchema(99))
        }
        XCTAssertNil(base.encryptedValues["payload"] as? Data)
    }

    func testLegacySystemFieldsStillRestoreWithoutSchemaMetadata() throws {
        let source = makeTabRecord()
        let cloud = try BrowserCloudRecordCodec().record(for: source)
        let archived = CloudRecordFields(record: cloud)
        let legacy = CloudRecordFields(recordName: archived.recordName, fields: archived.fields, schemaVersion: nil)
        let base = try XCTUnwrap(legacy.record(for: cloud.recordID))
        XCTAssertEqual(
            BrowserCloudRecordCodec().syncRecord(
                from: try BrowserCloudRecordCodec().record(for: source, reusing: base)), source)
    }

    private static let space = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private static let device = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    private func makeTabRecord() -> SyncRecord {
        SyncRecord(
            kind: .tab, id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!, spaceID: Self.space,
            version: SyncVersion(clock: 1, deviceID: Self.device), schema: 1,
            body: Data(#"{"type":"tab","value":{}}"#.utf8),
            isTombstone: false)
    }

    private func makeTombstone() -> SyncRecord {
        SyncRecord(
            kind: .tab, id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, spaceID: Self.space,
            version: SyncVersion(clock: 42, deviceID: Self.device), schema: 1,
            body: Data(#"{"deletedAt":500,"reason":"explicitDelete"}"#.utf8), isTombstone: true)
    }

    private func makeSpaceRecord() -> SyncRecord {
        SyncRecord(
            kind: .space, id: Self.space, spaceID: Self.space, version: SyncVersion(clock: 3, deviceID: Self.device),
            schema: 1,
            body: Data(#"{"type":"space","value":{}}"#.utf8), isTombstone: false)
    }
}
