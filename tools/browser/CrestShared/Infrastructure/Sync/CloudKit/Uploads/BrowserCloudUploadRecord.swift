import CloudKit
import Foundation

/// The record as the core's journal holds it.
struct BrowserCloudUploadRecord: BrowserCloudUpload {
    let syncRecord: SyncRecord

    func record(for recordID: CKRecord.ID, in batch: BrowserCloudUploadBatch) -> CKRecord? {
        // A record whose server copy a newer build wrote stays
        // pending, skipped.
        let base = batch.systemFields[recordID.recordName]?.record(for: recordID)
        return try? batch.codec.record(for: syncRecord, reusing: base)
    }
}
