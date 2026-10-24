import CloudKit
import Foundation

/// A record's server fields as CloudKit reads and writes them: the system
/// fields archived, and the record schema the server copy carries, which the
/// archive leaves out.
extension CloudRecordFields {
    // MARK: - Initializers

    /// The server fields of `record`.
    init(record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        self.init(
            recordName: record.recordID.recordName, fields: archiver.encodedData,
            // Kept beside the change tag so a skipped future record cannot
            // become a write base.
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue)
    }

    // MARK: - Actions - Records

    /// The record `id` these fields describe, carrying its server schema, to
    /// upload over; nil when they do not unarchive as that record.
    func record(for id: CKRecord.ID) -> CKRecord? {
        guard id.recordName == recordName else { return nil }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: fields)
            unarchiver.requiresSecureCoding = true
            guard let record = CKRecord(coder: unarchiver), record.recordID == id else { return nil }
            if let schemaVersion { record["schemaVersion"] = NSNumber(value: schemaVersion) }
            return record
        } catch {
            return nil
        }
    }
}
