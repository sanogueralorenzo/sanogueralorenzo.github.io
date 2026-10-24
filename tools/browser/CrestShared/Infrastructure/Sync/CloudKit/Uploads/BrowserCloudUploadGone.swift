import CloudKit
import Foundation

/// The journal no longer holds the record, so its pending save goes.
struct BrowserCloudUploadGone: BrowserCloudUpload {
    func record(for recordID: CKRecord.ID, in batch: BrowserCloudUploadBatch) -> CKRecord? {
        batch.syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
    }
}
