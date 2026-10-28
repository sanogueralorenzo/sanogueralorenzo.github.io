import CloudKit
import Foundation

/// The core would not answer for the record. Its save stays pending.
struct BrowserCloudUploadSkipped: BrowserCloudUpload {
    func record(for recordID: CKRecord.ID, in batch: BrowserCloudUploadBatch) -> CKRecord? {
        nil
    }
}
