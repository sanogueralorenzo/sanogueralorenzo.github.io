import CloudKit
import Foundation

// MARK: - Types

/// What one upload batch builds its records from: the codec, the server fields
/// each save uploads over, as the core keeps them, and the engine whose
/// pending saves it settles.
struct BrowserCloudUploadBatch: Sendable {
    let codec: BrowserCloudRecordCodec
    let systemFields: [String: CloudRecordFields]
    let syncEngine: CKSyncEngine
}

/// What a batch uploads for one pending save, which builds the record the
/// batch carries for it.
protocol BrowserCloudUpload: Sendable {
    /// The record `batch` carries for the pending save `recordID`, or nil when
    /// it carries none.
    func record(for recordID: CKRecord.ID, in batch: BrowserCloudUploadBatch) -> CKRecord?
}
