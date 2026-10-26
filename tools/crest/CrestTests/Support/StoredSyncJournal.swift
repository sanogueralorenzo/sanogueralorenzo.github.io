import Foundation

@testable import Crest

/// The sync journal a session file holds, read from its stored part the way
/// a test reads it: each record's reference, version and value in the
/// journal's form, and the records that wait to upload. Only the core writes
/// it.
struct StoredSyncJournal {
    // MARK: - Types

    enum ReadError: Error {
        case malformed(String)
    }

    /// One record the journal holds.
    struct Record {
        let reference: SyncRecordReference
        /// The Space the record belongs to.
        let spaceID: UUID
        let version: SyncVersion
        /// The payload's value, or nil for a tombstone.
        let value: [String: Any]?
        /// Why a tombstone's record was deleted, or nil for a payload.
        let deletionReason: SyncDeletionReason?

        var isTombstone: Bool { value == nil }
    }

    // MARK: - Variables

    let deviceID: UUID
    let records: [Record]
    /// The records that wait to upload.
    let pending: [SyncRecordReference]
    /// The records and the records that wait to upload as JSON with sorted
    /// keys, which two journals holding the same records spell the same way.
    let recordsJSON: Data

    // MARK: - Initializers

    /// The journal `data`, a stored journal part, holds.
    init(_ data: Data) throws {
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let device = (document["deviceID"] as? String).flatMap(UUID.init(uuidString:)),
            let records = document["records"] as? [[String: Any]],
            let pending = document["pendingRecordIDs"] as? [[String: Any]]
        else { throw ReadError.malformed("journal") }
        deviceID = device
        self.records = try records.map { record in
            guard let version = record["version"] as? [String: Any],
                let clock = (version["logicalClock"] as? NSNumber)?.uint64Value,
                let writer = (version["deviceID"] as? String).flatMap(UUID.init(uuidString:)),
                let space = ((record["spaceID"] as? [String: Any])?["rawValue"] as? String).flatMap(
                    UUID.init(uuidString:))
            else { throw ReadError.malformed("record") }
            return Record(
                reference: try Self.reference(record["id"]), spaceID: space,
                version: SyncVersion(clock: clock, deviceID: writer),
                value: (record["payload"] as? [String: Any])?["value"] as? [String: Any],
                deletionReason: SyncDeletionReason.named((record["tombstone"] as? [String: Any])?["reason"] as? String))
        }
        self.pending = try pending.map(Self.reference)
        recordsJSON = try JSONSerialization.data(withJSONObject: [records, pending], options: [.sortedKeys])
    }

    // MARK: - Actions

    /// The record of `kind` with identity `id`, or nil when the journal holds
    /// none.
    func record(_ kind: SyncRecordKind, _ id: UUID) -> Record? {
        records.first { $0.reference == SyncRecordReference(kind: kind, id: id) }
    }

    /// Whether the record of `kind` with identity `id` waits to upload.
    func isPending(_ kind: SyncRecordKind, _ id: UUID) -> Bool {
        pending.contains(SyncRecordReference(kind: kind, id: id))
    }

    /// The journal of device `deviceID` before it staged anything, as the
    /// core writes a new one, for a file a test gives its first session. It
    /// syncs the current tabs unless `syncsCurrentTabs` is false.
    static func fresh(deviceID: UUID, syncsCurrentTabs: Bool = true) -> Data {
        let preferences: [String: Any] = [
            "savedStructure": true, "currentTabs": syncsCurrentTabs, "historyAndArchive": true,
            "extensionSettings": true,
        ]
        let document: [String: Any] = [
            "schemaVersion": 1, "deviceID": deviceID.uuidString, "logicalClock": 0, "preferences": preferences,
            "records": [Any](), "pendingRecordIDs": [Any](),
        ]
        do { return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]) } catch {
            preconditionFailure("A fresh journal always encodes: \(error)")
        }
    }

    private static func reference(_ node: Any?) throws -> SyncRecordReference {
        guard let id = node as? [String: Any], let kind = SyncRecordKind.named(id["kind"] as? String),
            let value = (id["value"] as? String).flatMap(UUID.init(uuidString:))
        else { throw ReadError.malformed("identity") }
        return SyncRecordReference(kind: kind, id: value)
    }
}
