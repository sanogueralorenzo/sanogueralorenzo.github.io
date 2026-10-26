import CloudKit
import Foundation

/// The records one upload batch carries. CloudKit's batch asks for them one at
/// a time, in the order its pending saves wait, and stops once the batch is
/// full, so the core is asked for them a chunk at a time as the batch reaches
/// them: a batch reads only its own records, however many wait.
actor BrowserCloudUploadSource {
    // MARK: - Static Variables

    /// How many records one question to the core names.
    static let chunkSize = 200

    // MARK: - Variables

    private let core: CrestCore
    private let codec: BrowserCloudRecordCodec
    /// The pending saves, in the order the batch reaches them.
    private let saves: [CKRecord.ID]
    /// Where each pending save stands in `saves`.
    private let positions: [String: Int]
    /// What the core answered for each save it was asked about, by record name.
    private var answered: [String: SyncRecord] = [:]
    private var gone: Set<String> = []
    /// How many saves, from the first, the core was asked about.
    private var asked = 0

    // MARK: - Initializers

    init(core: CrestCore, codec: BrowserCloudRecordCodec, saves: [CKRecord.ID]) {
        self.core = core
        self.codec = codec
        self.saves = saves
        positions = Dictionary(saves.enumerated().map { ($1.recordName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Actions - Uploads

    /// Asks the core for the first chunk. Throws the refusal that keeps the
    /// batch from running at all.
    func prepare() throws(Rejection) {
        try ask(from: 0)
    }

    /// What the batch uploads for `recordID`. A save whose name no record of
    /// Crest's has is gone.
    func upload(for recordID: CKRecord.ID) -> any BrowserCloudUpload {
        guard codec.reference(for: recordID) != nil else { return BrowserCloudUploadGone() }
        let name = recordID.recordName
        if answered[name] == nil, !gone.contains(name), let position = positions[name], position >= asked {
            do { try ask(from: position) } catch { return BrowserCloudUploadSkipped() }
        }
        if gone.contains(name) { return BrowserCloudUploadGone() }
        return answered[name].map { BrowserCloudUploadRecord(syncRecord: $0) } ?? BrowserCloudUploadSkipped()
    }

    /// Asks the core for the chunk of saves that starts at `position`.
    private func ask(from position: Int) throws(Rejection) {
        guard position < saves.count else { return }
        let end = min(position + Self.chunkSize, saves.count)
        let batch = try core.query(RecordsToUpload(records: saves[position..<end].compactMap(codec.reference(for:))))
        for record in batch.records {
            answered[codec.recordName(of: SyncRecordReference(kind: record.kind, id: record.id))] = record
        }
        for reference in batch.gone { gone.insert(codec.recordName(of: reference)) }
        asked = max(asked, end)
    }
}
