import CloudKit
import Foundation
import XCTest

@testable import Crest

/// How the transport maps the core's synced records to CloudKit records: the
/// envelope's fields and types, the owning Space's reference, zone isolation,
/// the server's system fields, and the payload or tombstone bytes the core
/// spelled, copied as they are. What a payload holds is the core's codec's.
final class BrowserCloudRecordCodecTests: XCTestCase {
    /// Members a newer build writes survive this device's edit: the core keeps
    /// them through the CloudKit mapping and uploads them again.
    @MainActor
    func testAdditiveCloudPayloadSurvivesCoreEditAndUpload() async throws {
        let session = SessionState.Seed.preview
        let sender = try BrowserStoredSessionHarness(seed: session)
        await sender.store.flushPendingSyncPersistence()
        let receiver = try BrowserStoredSessionHarness(seed: session)
        await receiver.store.flushPendingSyncPersistence()
        let codec = BrowserCloudRecordCodec()
        let space = SyncRecordReference(kind: .space, id: session.spaces[0].id)
        let upload = try XCTUnwrap(try sender.core.query(RecordsToUpload(records: [space])).records.first)
        let cloud = try codec.record(for: upload)
        var raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(cloud.encryptedValues["payload"] as? Data)) as? [String: Any])
        var body = try XCTUnwrap(raw["value"] as? [String: Any])
        var branding = try XCTUnwrap(body["branding"] as? [String: Any])
        var crest = try XCTUnwrap(branding["crest"] as? [String: Any])
        raw["futureEnvelope"] = ["values": [true, "retained", NSNull()] as [Any]]
        body["futureSpace"] = NSNumber(value: UInt64.max)
        crest["futureCrest"] = ["enabled": true]
        branding["crest"] = crest
        body["branding"] = branding
        raw["value"] = body
        cloud.encryptedValues["payload"] = try JSONSerialization.data(withJSONObject: raw) as CKRecordValue
        // A newer writer advances the record's version along with its data.
        cloud["logicalClock"] = NSNumber(value: upload.version.clock + 1_000)

        try receiver.deliverNow(MergeSyncRecords(records: [try XCTUnwrap(codec.syncRecord(from: cloud))]))
        receiver.store.updateSpaceIdentity(
            session.spaces[0].id, name: "Renamed by the older client", symbol: session.spaces[0].settings.symbol,
            accent: session.spaces[0].settings.accent)
        await receiver.store.flushPendingSyncPersistence()

        let saved = try XCTUnwrap(try receiver.core.query(RecordsToUpload(records: [space])).records.first)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(codec.record(for: saved).encryptedValues["payload"] as? Data))
                as? [String: Any])
        let value = try XCTUnwrap(result["value"] as? [String: Any])
        let resultCrest = try XCTUnwrap((value["branding"] as? [String: Any])?["crest"] as? [String: Any])
        XCTAssertEqual(value["name"] as? String, "Renamed by the older client")
        XCTAssertEqual((value["futureSpace"] as? NSNumber)?.uint64Value, UInt64.max)
        XCTAssertEqual((resultCrest["futureCrest"] as? [String: Bool])?["enabled"], true)
        XCTAssertNotNil(result["futureEnvelope"])
    }

    @MainActor
    func testFullSpaceCustomizationSyncsBetweenStoresAndSurvivesReload() async throws {
        let session = SessionState.Seed.preview
        let spaceID = session.spaces[0].id
        let senderHarness = try BrowserStoredSessionHarness(seed: session)
        await senderHarness.store.flushPendingSyncPersistence()
        let receiverHarness = try BrowserStoredSessionHarness(seed: session)
        let sender = senderHarness.store
        let receiver = receiverHarness.store
        let codec = BrowserCloudRecordCodec()
        // What one device uploads, as CloudKit hands it to the other.
        func throughCloud(_ records: [SyncRecord]) throws -> [SyncRecord] {
            try records.map { try XCTUnwrap(codec.syncRecord(from: codec.record(for: $0))) }
        }
        func waiting(_ harness: BrowserStoredSessionHarness) throws -> [SyncRecord] {
            try harness.core.query(RecordsToUpload(records: harness.core.query(PendingUploads()).records)).records
        }
        // The look a store's Space wears.
        func look(in store: BrowserStore) -> SpaceBranding? {
            store.spaceModel(spaceID).map(\.settings.look)
        }
        try receiverHarness.deliverNow(MergeSyncRecords(records: throughCloud(waiting(senderHarness))))
        try senderHarness.acknowledgePendingUploads()

        // Every member of a look set away from the house look's.
        var branding = SpaceAccent.indigo.house
        branding.colors = [.ink, .ocean, .gold]
        branding.bannerPattern = .lozenges
        branding.bannerStrength = 0.63
        branding.readabilityFade = 0.37
        branding.themeMode = .gradient
        branding.gradientAngle = 217
        branding.showsTexture = true
        branding.iconStyle = .layeredCrest
        branding.symbolColor = .ember
        branding.folderColorIntensity = 0.71
        branding.textColorMode = .light
        branding.hasCustomAppearance = true
        branding.crest = SpaceCrest(
            backplate: .frenchShield, fieldDivision: .gyronny, ordinary: .pall, trim: .beaded, symbol: .direwolf,
            chargeLayout: .trio, backplateColorIndex: 1, secondaryFieldColorIndex: 2, ordinaryColorIndex: 3,
            trimColorIndex: 0, symbolColorIndex: 2, startingPresetID: "winter", edgeColorIndex: 3,
            palette: [.ember, .gold, .ink, .sand], charge: nil, plateScale: 0.85, edgeWidth: 0.43, divisionCount: 6,
            finish: .sheen, ordinaryWidth: 1.2, trimWeight: 1.3, trimDetail: 18, chargeScale: 1.1, chargeOffset: -0.12,
            chargeWeight: .light, sheenAngle: 125, sealTeeth: 16, showsOutline: true, depth: .lifted)
        let charges =
            CrestSymbol.all.map(CrestCharge.heraldic)
            + [.system("hammer.fill"), .emoji("🐉"), .monogram("PD", .serif), .none]
        for charge in charges {
            branding.crest.charge = charge
            sender.updateSpaceBranding(branding, in: spaceID)
            await sender.flushPendingSyncPersistence()
            let pending = try waiting(senderHarness)
            XCTAssertEqual(pending.map(\.kind), [.space])
            try receiverHarness.deliverNow(MergeSyncRecords(records: throughCloud(pending)))
            try senderHarness.acknowledgePendingUploads()

            let expected = try XCTUnwrap(look(in: sender))
            XCTAssertEqual(look(in: receiver), expected, "Charge: \(charge)")
            await receiver.flushPendingSyncPersistence()
            let reloaded = try XCTUnwrap(try receiverHarness.stored().session.space(id: spaceID))
            XCTAssertEqual(reloaded.settings, receiver.spaceModel(spaceID)?.value.seed.settings)
            XCTAssertEqual(reloaded.profileID, session.spaces[0].profileID)
        }

        // Editing on the receiving device must produce a fresh Space record too.
        var returnedBranding = try XCTUnwrap(look(in: receiver))
        returnedBranding.iconStyle = .simpleSymbol
        returnedBranding.symbolColor = .gold
        returnedBranding.crest.palette = nil
        returnedBranding.crest.charge = .system("leaf.fill")
        receiver.updateSpaceIdentity(spaceID, name: "Garden", symbol: "leaf.fill", accent: .teal)
        receiver.updateSpaceBranding(returnedBranding, in: spaceID)
        await receiver.flushPendingSyncPersistence()
        try senderHarness.deliverNow(MergeSyncRecords(records: throughCloud(waiting(receiverHarness))))
        XCTAssertEqual(look(in: sender), returnedBranding.normalized())
        XCTAssertEqual(sender.spaceModel(spaceID)?.settings.name, "Garden")
        XCTAssertEqual(sender.spaceModel(spaceID)?.settings.symbol, "leaf.fill")
        XCTAssertEqual(sender.spaceModel(spaceID)?.settings.accent, .teal)
    }

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

    func testChildRecordCarriesAReferenceToItsOwningSpace() throws {
        let source = makeTabRecord()
        let reference = try XCTUnwrap(try BrowserCloudRecordCodec().record(for: source)["space"] as? CKRecord.Reference)

        XCTAssertEqual(reference.recordID.zoneID, BrowserCloudRecordCodec.zoneID)
        XCTAssertEqual(reference.recordID.recordName, "space:\(source.spaceID.uuidString.lowercased())")
        XCTAssertEqual(reference.action, .none)
        XCTAssertNil(try BrowserCloudRecordCodec().record(for: makeSpaceRecord())["space"])
    }

    func testCodecReusesLastKnownServerRecordSystemFields() throws {
        let source = makeTabRecord()
        let codec = BrowserCloudRecordCodec()
        let base = CKRecord(
            recordType: "CrestTab", recordID: codec.recordID(for: SyncRecordReference(kind: .tab, id: source.id)))

        let encoded = try codec.record(for: source, reusing: base)

        XCTAssertTrue(encoded === base)
        XCTAssertEqual(codec.syncRecord(from: encoded), source)
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

    func testSystemFieldsPersistWithoutCopyingDomainPayload() throws {
        let cloudRecord = try BrowserCloudRecordCodec().record(for: makeTabRecord())
        let fields = CloudRecordFields(record: cloudRecord)

        let restored = try XCTUnwrap(fields.record(for: cloudRecord.recordID))

        XCTAssertEqual(restored.recordID, cloudRecord.recordID)
        XCTAssertNil(restored.encryptedValues["payload"] as? Data)
        let other = CKRecord.ID(recordName: "tab:other", zoneID: cloudRecord.recordID.zoneID)
        XCTAssertNil(fields.record(for: other))
    }

    /// Writing over the server's copy takes the schema the record needs now,
    /// so a folder that was open and is saved again is read by older clients.
    func testWritingOverTheServersCopyTakesTheSchemaTheRecordNeedsNow() throws {
        let codec = BrowserCloudRecordCodec()
        let open = SyncRecord(
            kind: .folder, id: UUID(), spaceID: UUID(), version: SyncVersion(clock: 1, deviceID: UUID()), schema: 2,
            body: Data("{}".utf8), isTombstone: false)
        let cloud = try codec.record(for: open)
        let saved = SyncRecord(
            kind: .folder, id: open.id, spaceID: open.spaceID,
            version: SyncVersion(clock: 2, deviceID: open.version.deviceID),
            schema: 1, body: Data("{}".utf8), isTombstone: false)

        XCTAssertEqual((try codec.record(for: saved, reusing: cloud)["schemaVersion"] as? NSNumber)?.intValue, 1)
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
