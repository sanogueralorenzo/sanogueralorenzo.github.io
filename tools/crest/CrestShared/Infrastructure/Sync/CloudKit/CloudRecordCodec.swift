import CloudKit
import Foundation

// MARK: - Types

enum BrowserCloudRecordCodecError: Error, Equatable {
    /// The server's last copy of a record is another record's.
    case mismatchedBaseRecord(String)
    /// A newer build wrote the server's last copy for a schema this build
    /// does not know, so this build must not write over it.
    case newerSchema(Int)
}

/// Maps the core's synced records to CloudKit records and back. It writes and
/// reads the envelope, the fields every client places a record by, and copies
/// the payload or tombstone the core spelled into the encrypted values as
/// bytes; it never reads what they hold.
struct BrowserCloudRecordCodec: Sendable {
    // MARK: - Static Variables

    /// The newest schema this build writes, which a base record from a newer
    /// build exceeds.
    static let currentSchemaVersion = 3

    static let zoneName = BrowserCloudSyncConfiguration.defaultZoneName
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)

    // MARK: - Types

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let spaceID = "spaceID"
        static let logicalClock = "logicalClock"
        static let deviceID = "deviceID"
        static let payload = "payload"
        static let tombstone = "tombstone"
        static let spaceReference = "space"
    }

    // MARK: - Variables

    let recordZoneID: CKRecordZone.ID
    var recordZone: CKRecordZone { CKRecordZone(zoneID: recordZoneID) }

    // MARK: - Initializers

    init(zoneName: String = Self.zoneName) {
        recordZoneID = CKRecordZone.ID(zoneName: zoneName)
    }

    // MARK: - Actions - Records

    /// `source` as the CloudKit record that uploads it, written over
    /// `baseRecord`, the last copy the server returned, when there is one.
    /// Throws when the base record is another record's or a newer build wrote
    /// it for a schema this build does not know.
    func record(for source: SyncRecord, reusing baseRecord: CKRecord? = nil) throws -> CKRecord {
        let reference = SyncRecordReference(kind: source.kind, id: source.id)
        let recordID = recordID(for: reference)
        let record: CKRecord
        if let baseRecord {
            guard baseRecord.recordID == recordID, baseRecord.recordType == source.kind.cloudRecordType else {
                throw BrowserCloudRecordCodecError.mismatchedBaseRecord(recordID.recordName)
            }
            if let schema = (baseRecord[Field.schemaVersion] as? NSNumber)?.intValue, schema > Self.currentSchemaVersion
            {
                throw BrowserCloudRecordCodecError.newerSchema(schema)
            }
            record = baseRecord
        } else {
            record = CKRecord(recordType: source.kind.cloudRecordType, recordID: recordID)
        }
        record[Field.schemaVersion] = NSNumber(value: source.schema)
        record[Field.spaceID] = source.spaceID.uuidString.lowercased() as CKRecordValue
        record[Field.logicalClock] = NSNumber(value: source.version.clock)
        record[Field.deviceID] = source.version.deviceID.uuidString.lowercased() as CKRecordValue
        record[Field.spaceReference] =
            source.kind.namesItsSpace
            ? nil
            : CKRecord.Reference(
                recordID: self.recordID(for: SyncRecordReference(kind: .space, id: source.spaceID)), action: .none)
        record.encryptedValues[Field.payload] = source.isTombstone ? nil : source.body as CKRecordValue
        record.encryptedValues[Field.tombstone] = source.isTombstone ? source.body as CKRecordValue : nil
        return record
    }

    /// The synced record `record` carries, or nil when its envelope is not one
    /// of Crest's: another zone, an unknown type, a name that is not its
    /// kind's, a missing schema, clock or identity, or both or neither of a
    /// payload and a tombstone. What the payload holds is the core's to read.
    func syncRecord(from record: CKRecord) -> SyncRecord? {
        guard let reference = reference(for: record.recordID), record.recordType == reference.kind.cloudRecordType,
            let schema = (record[Field.schemaVersion] as? NSNumber)?.intValue,
            let space = (record[Field.spaceID] as? String).flatMap(UUID.init(uuidString:)),
            let clock = (record[Field.logicalClock] as? NSNumber)?.uint64Value,
            let device = (record[Field.deviceID] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        let payload = record.encryptedValues[Field.payload] as? Data
        let tombstone = record.encryptedValues[Field.tombstone] as? Data
        guard let body = payload ?? tombstone, (payload == nil) != (tombstone == nil) else { return nil }
        return SyncRecord(
            kind: reference.kind, id: reference.id, spaceID: space,
            version: SyncVersion(clock: clock, deviceID: device),
            schema: schema, body: body, isTombstone: tombstone != nil)
    }

    // MARK: - Actions - Envelopes

    /// How CloudKit names the record `reference` names: its kind, then its
    /// identity in lowercase.
    func recordName(of reference: SyncRecordReference) -> String {
        "\(reference.kind.name):\(reference.id.uuidString.lowercased())"
    }

    /// The CloudKit identity of the record `reference` names, in this codec's
    /// zone.
    func recordID(for reference: SyncRecordReference) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(of: reference), zoneID: recordZoneID)
    }

    /// The record a CloudKit identity in this codec's zone names, or nil for an
    /// identity no record of Crest's has.
    func reference(for recordID: CKRecord.ID) -> SyncRecordReference? {
        guard recordID.zoneID == recordZoneID else { return nil }
        let parts = recordID.recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = SyncRecordKind.named(String(parts[0])),
            let id = UUID(uuidString: String(parts[1]))
        else { return nil }
        return SyncRecordReference(kind: kind, id: id)
    }

    /// The record the cloud saved, at the version it saved, read from its
    /// envelope alone; nil for a record that is not one of Crest's.
    func uploadedRecord(_ record: CKRecord) -> UploadedRecord? {
        guard let reference = reference(for: record.recordID), record.recordType == reference.kind.cloudRecordType,
            let clock = (record[Field.logicalClock] as? NSNumber)?.uint64Value,
            let device = (record[Field.deviceID] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        return UploadedRecord(record: reference, version: SyncVersion(clock: clock, deviceID: device))
    }
}
