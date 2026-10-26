import CloudKit

/// Every record in Crest's zone, as the core takes them, and how many records
/// the zone holds that are not Crest's to read at all.
struct BrowserCloudSnapshot: Sendable {
    let records: [SyncRecord]
    /// Records whose envelope is not one of Crest's, which nothing reads.
    let unreadable: Int
}

struct BrowserCloudSnapshotLoader: Sendable {
    let database: CKDatabase
    let codec: BrowserCloudRecordCodec

    init(database: CKDatabase, codec: BrowserCloudRecordCodec = BrowserCloudRecordCodec()) {
        self.database = database
        self.codec = codec
    }

    /// Reads every record in Crest's zone. A record whose envelope is not one
    /// of Crest's is counted, not returned; what a payload holds is the core's
    /// to read, and the core decides whether a snapshot is whole.
    func load() async throws -> BrowserCloudSnapshot {
        var token: CKServerChangeToken?
        var recordsByName: [String: SyncRecord] = [:]
        var unreadable: Set<String> = []
        var hasMore = true
        while hasMore {
            let changes = try await database.recordZoneChanges(
                inZoneWith: codec.recordZoneID,
                since: token,
                desiredKeys: nil,
                resultsLimit: nil
            )
            for (recordID, result) in changes.modificationResultsByID {
                // A fetch that failed is still an incomplete snapshot, and an
                // incomplete snapshot must never drive an overwrite decision.
                let record = try result.get().record
                if let synced = codec.syncRecord(from: record) {
                    recordsByName[recordID.recordName] = synced
                    unreadable.remove(recordID.recordName)
                } else {
                    recordsByName.removeValue(forKey: recordID.recordName)
                    unreadable.insert(recordID.recordName)
                }
            }
            for deletion in changes.deletions {
                recordsByName.removeValue(forKey: deletion.recordID.recordName)
                unreadable.remove(deletion.recordID.recordName)
            }
            token = changes.changeToken
            hasMore = changes.moreComing
        }
        return BrowserCloudSnapshot(
            records: recordsByName.sorted { $0.key < $1.key }.map(\.value), unreadable: unreadable.count)
    }
}
