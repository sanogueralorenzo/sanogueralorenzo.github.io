import CloudKit
import Foundation

/// Runs CloudKit's sync engine over the journal of the session the core keeps
/// in its file. It never reads the journal itself: it asks the core which
/// records wait to upload and for the ones each batch carries, sends the
/// core what the cloud sent and saved as intents, and hears what changed
/// through the core's wake, never through their answers. The core also keeps
/// the transport's own state in its device store: the engine's saved cursor,
/// each record's server fields, and when a full pull, an account decision or
/// this device's overwrite holds; `transport` is what it last answered. Every
/// call into the core runs off the main thread.
actor BrowserCloudSyncEngine {
    private let database: @Sendable () -> CKDatabase
    private let core: CrestCore
    private let codec: BrowserCloudRecordCodec
    private let automaticallySync: Bool
    private let statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)?
    private let activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)?
    private var transport: CloudTransportState
    private var engine: CKSyncEngine?
    private var eventFailureDescription: String?
    private var isPullingSnapshot = false
    private var isStopped = false
    private(set) var status: BrowserCloudSyncStatus = .stopped

    init(
        database: @autoclosure @escaping @Sendable () -> CKDatabase,
        core: CrestCore,
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec()
        self.database = database
        self.core = core
        self.automaticallySync = automaticallySync
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        transport = try core.query(CloudTransport())
        if transport.awaitsAccountDecision {
            status = .pausedForAccountConfirmation
        }
    }

    init(
        configuration: BrowserCloudSyncConfiguration,
        core: CrestCore,
        automaticallySync: Bool = true,
        statusHandler: (@Sendable (BrowserCloudSyncStatus) async -> Void)? = nil,
        activityHandler: (@Sendable (BrowserCloudSyncActivity) async -> Void)? = nil
    ) throws {
        self.codec = BrowserCloudRecordCodec(zoneName: configuration.zoneName)
        self.database = {
            CKContainer(identifier: configuration.containerIdentifier).privateCloudDatabase
        }
        self.core = core
        self.automaticallySync = automaticallySync
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        transport = try core.query(CloudTransport())
        if transport.awaitsAccountDecision {
            status = .pausedForAccountConfirmation
        }
    }

    func start() async {
        isStopped = false
        guard !transport.awaitsAccountDecision else {
            await updateStatus(.pausedForAccountConfirmation)
            return
        }
        do {
            // An overwrite whose records all uploaded before the last launch
            // ended no longer holds.
            try await send(SettleCloudOverwrite())
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            return
        }
        guard !isStopped else { return }
        let syncEngine = initializedEngine()
        if transport.requiresFullPull {
            do {
                _ = try await pullFromICloud()
            } catch {
                await updateStatus(.failed(Self.describe(error)))
                return
            }
        }
        if transport.engineState == nil {
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(codec.recordZone)
            ])
        }
        await enqueueLocalChanges(on: syncEngine)
        // The engine fetches on a push, and one sent while Crest was closed
        // never arrives; it sends when a save is first queued, and saves
        // queued while a full pull held them back are not new. A start
        // fetches and sends once, as Sync Now does, and the status says how
        // that went.
        try? await exchange(on: syncEngine)
    }

    func stop() async {
        isStopped = true
        await engine?.cancelOperations()
        engine = nil
    }

    func notifyLocalChanges() async {
        guard !isStopped, !transport.awaitsAccountDecision else { return }
        let syncEngine = initializedEngine()
        await enqueueLocalChanges(on: syncEngine)
    }

    func syncNow() async throws {
        guard !isStopped else { throw CancellationError() }
        guard !transport.awaitsAccountDecision else {
            await updateStatus(.pausedForAccountConfirmation)
            return
        }
        try await exchange(on: initializedEngine())
    }

    /// Fetches what changed in iCloud, then sends what waits to upload,
    /// recovering with a full pull first when one is required. Reports
    /// syncing, then idle or the failure it throws.
    private func exchange(on syncEngine: CKSyncEngine) async throws {
        eventFailureDescription = nil
        await updateStatus(.syncing)
        do {
            if transport.requiresFullPull {
                _ = try await pullFromICloud()
            }
            try await syncEngine.fetchChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            guard !isStopped else { throw CancellationError() }
            guard !transport.awaitsAccountDecision else {
                await updateStatus(.pausedForAccountConfirmation)
                return
            }
            // `fetchChanges` and `sendChanges` return normally even when the
            // events they drove failed, so reporting success from here would
            // paint "Up to date" over records that never landed.
            if let failure = eventFailureDescription {
                throw BrowserCloudSyncError.remoteChangeNotApplied(failure)
            }
            guard !transport.requiresFullPull else {
                throw BrowserCloudSyncError.remoteChangeNotApplied(
                    "Pull from iCloud to recover an incomplete download.")
            }
            await enqueueLocalChanges(on: syncEngine)
            try await syncEngine.sendChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            guard !isStopped else { throw CancellationError() }
            if let failure = eventFailureDescription {
                throw BrowserCloudSyncError.remoteChangeNotApplied(failure)
            }
            await updateStatus(.idle)
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            throw error
        }
    }

    /// Downloads every record in Crest's zone and merges it, then sends what
    /// waits to upload. Answers how many records the zone held.
    func pullFromICloud() async throws -> Int {
        guard !isStopped, !transport.awaitsAccountDecision, !isPullingSnapshot else {
            throw BrowserCloudSyncError.remoteChangeNotApplied("Sync is paused.")
        }
        isPullingSnapshot = true
        defer { isPullingSnapshot = false }
        await updateStatus(.syncing)
        do {
            let snapshot = try await BrowserCloudSnapshotLoader(database: database(), codec: codec).load()
            // An incomplete snapshot must never decide what this device holds;
            // the core refuses one whose payloads it cannot all read.
            guard snapshot.unreadable == 0 else {
                throw BrowserCloudSyncError.remoteChangeNotApplied(
                    "Some iCloud records could not be read. Update Crest on all devices and try again.")
            }
            let records = snapshot.records
            guard !isStopped, !transport.awaitsAccountDecision else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("The iCloud account changed during the download.")
            }
            try await mergeDownloadedRecords(records, isFullSnapshot: true)
            guard !transport.requiresFullPull else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("Some incoming changes still need to be recovered.")
            }
            eventFailureDescription = nil
            isPullingSnapshot = false
            let syncEngine = initializedEngine()
            await enqueueLocalChanges(on: syncEngine)
            await activityHandler?(.fetched(recordCount: records.count))
            // Nothing uploads while a pull runs or is required, and the saves
            // that waited are not offered again on their own.
            try await syncEngine.sendChanges(.init(scope: .zoneIDs([codec.recordZoneID])))
            if let failure = eventFailureDescription {
                throw BrowserCloudSyncError.remoteChangeNotApplied(failure)
            }
            await updateStatus(.idle)
            return records.count
        } catch {
            await updateStatus(.failed(Self.describe(error)))
            throw error
        }
    }

    /// The core notes that a full pull must recover the merge before it is
    /// applied: state-update events may persist a newer cursor even when this
    /// merge fails or the app exits. A full snapshot is refused whole when the
    /// core cannot read all of it. Answers the records the core left out.
    @discardableResult
    func mergeDownloadedRecords(
        _ records: [SyncRecord],
        isFullSnapshot: Bool = false
    ) async throws -> SyncRecordsSkipped? {
        let merge = try await beginMerge()
        let receipts: [Change]
        do {
            if isFullSnapshot {
                receipts = try await deliver(MergeCloudSnapshot(records: records))
            } else {
                receipts = try await deliver(MergeSyncRecords(records: records))
            }
            guard !isStopped, !transport.awaitsAccountDecision else {
                throw BrowserCloudSyncError.remoteChangeNotApplied("Sync stopped while applying downloaded content.")
            }
        } catch {
            _ = try? await send(FinishCloudMerge(mergeID: merge, succeeded: false, fullSnapshot: isFullSnapshot))
            throw error
        }
        try await send(FinishCloudMerge(mergeID: merge, succeeded: true, fullSnapshot: isFullSnapshot))
        return CloudTransportReceipts(receipts).skipped
    }

    func process(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        guard !isStopped else { return }
        do {
            switch event {
            case .stateUpdate(let event):
                try await send(SaveCloudEngineState(serialization: JSONEncoder().encode(event.stateSerialization)))
            case .accountChange(let event):
                if try await handleAccountChange(event) {
                    await activityHandler?(.accountChanged)
                }
            case .fetchedRecordZoneChanges(let event):
                try await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)
            case .fetchedDatabaseChanges(let event):
                try await handleFetchedDatabaseChanges(event, syncEngine: syncEngine)
            case .sentRecordZoneChanges(let event):
                try await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
            case .willFetchChanges,
                .willFetchRecordZoneChanges,
                .didFetchRecordZoneChanges,
                .didFetchChanges,
                .willSendChanges,
                .didSendChanges,
                .sentDatabaseChanges:
                break
            @unknown default:
                break
            }
        } catch {
            eventFailureDescription = Self.describe(error)
            await updateStatus(.failed(Self.describe(error)))
        }
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = .zoneIDs(context.options.scope.contains(codec.recordZoneID) ? [codec.recordZoneID] : [])
        return options
    }

    func makeRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !isStopped, !transport.awaitsAccountDecision,
            !transport.requiresFullPull, !isPullingSnapshot
        else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            switch $0 {
            case .saveRecord(let id), .deleteRecord(let id):
                return id.zoneID == codec.recordZoneID && context.options.scope.contains($0)
            @unknown default:
                return false
            }
        }
        // Every stage the core queued settles first, so the batch carries the
        // newest records. A core that refuses to answer uploads nothing.
        await core.settleSync()
        let source = BrowserCloudUploadSource(
            core: core, codec: codec,
            saves: changes.compactMap {
                guard case .saveRecord(let id) = $0 else { return nil }
                return id
            })
        do { try await source.prepare() } catch { return nil }
        guard !isStopped, !transport.awaitsAccountDecision,
            !transport.requiresFullPull, !isPullingSnapshot
        else { return nil }
        // The server fields each save uploads over, as the core keeps them. A
        // core that refuses to answer uploads nothing.
        let saves = changes.compactMap { change -> CKRecord.ID? in
            guard case .saveRecord(let id) = change else { return nil }
            return id
        }
        guard let kept = try? core.query(CloudFieldsOf(recordNames: saves.map(\.recordName))) else { return nil }
        let systemFields = Dictionary(kept.records.map { ($0.recordName, $0) }, uniquingKeysWith: { _, last in last })
        // The sendable closure takes a copy of the codec in the batch, never a
        // local named like the property: Swift 6.2 reads a same-named local
        // declared later in the scope as the one the filter above captures,
        // and refuses it.
        let batch = BrowserCloudUploadBatch(codec: codec, systemFields: systemFields, syncEngine: syncEngine)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await source.upload(for: recordID).record(for: recordID, in: batch)
        }
    }

    private func initializedEngine() -> CKSyncEngine {
        if let engine { return engine }
        var configuration = CKSyncEngine.Configuration(
            database: database(),
            // A saved state this build cannot read fetches everything again.
            stateSerialization: transport.engineState.flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            },
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        let result = CKSyncEngine(configuration)
        engine = result
        return result
    }

    private func enqueueLocalChanges(on syncEngine: CKSyncEngine) async {
        // A core that refuses to answer queues nothing; the next journal change
        // asks again.
        guard let pending = try? await pendingUploads() else { return }
        guard !isStopped, !transport.awaitsAccountDecision else { return }
        syncEngine.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(codec.recordID(for: $0)) })
    }

    /// The records the core's journal holds waiting to upload, once every
    /// stage the core queued has settled.
    private func pendingUploads() async throws -> [SyncRecordReference] {
        await core.settleSync()
        return try core.query(PendingUploads()).records
    }

    /// Sends the core an intent from the cloud on a utility thread: the core
    /// computes it on the thread that sends it, never the main thread, and what
    /// it changed reaches the main thread through its wake.
    @discardableResult
    private func deliver(_ intent: some CloudSyncIntent) async throws -> [Change] {
        let core = core
        return try await Task.detached(priority: .utility) { try core.deliver(intent) }.value
    }

    /// Sends the core an intent about the transport's own state on a utility
    /// thread, and keeps the state it answered.
    @discardableResult
    private func send(_ intent: some CloudTransportIntent) async throws -> CloudTransportState {
        let core = core
        let receipts = try await Task.detached(priority: .utility) { try core.transport(intent) }.value
        if let state = CloudTransportReceipts(receipts).transport { transport = state }
        return transport
    }

    /// Asks the core to note a merge before it is applied, and answers the
    /// merge's name.
    private func beginMerge() async throws -> Int64 {
        let core = core
        let receipts = try await Task.detached(priority: .utility) { try core.transport(BeginCloudMerge()) }.value
        let noted = CloudTransportReceipts(receipts)
        if let state = noted.transport { transport = state }
        guard let merge = noted.mergeID else { preconditionFailure("The core began a merge without naming it.") }
        return merge
    }

    /// Keeps the server fields `changes` collected, in the core's device store.
    private func record(_ changes: inout CloudFieldChanges) async throws {
        guard !changes.isEmpty else { return }
        try await send(RecordCloudFields(updated: Array(changes.updated.values), removed: Array(changes.removed)))
        changes = CloudFieldChanges()
    }

    /// What the person is told of a failure: a refusal in the core's own words,
    /// anything else as it describes itself.
    private static func describe(_ error: any Error) -> String {
        (error as? Rejection)?.explanation ?? String(describing: error)
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        guard !transport.awaitsAccountDecision else { return }
        // Each record is read on its own, so one this build cannot read never
        // costs the batch it arrived in: the change token advances whether or
        // not the records were applied, so a batch abandoned that way would
        // never be offered again.
        var records: [SyncRecord] = []
        var unreadable = 0
        var fromNewerBuild = 0
        var fields = CloudFieldChanges()
        for modification in event.modifications {
            guard modification.record.recordID.zoneID == codec.recordZoneID else { continue }
            fields.update(with: modification.record)
            if let record = codec.syncRecord(from: modification.record) {
                records.append(record)
            } else {
                unreadable += 1
            }
        }
        // The server fields are kept before the merge, which may fail.
        try await record(&fields)
        if !records.isEmpty {
            // While this device's copy overwrites the cloud's, fetched content
            // is not merged.
            if !transport.overwritesCloud, let skipped = try await mergeDownloadedRecords(records) {
                unreadable += skipped.unreadable
                fromNewerBuild += skipped.fromNewerBuild
            }
            await enqueueLocalChanges(on: syncEngine)
            let applied = records.count - unreadable - fromNewerBuild
            if !transport.requiresFullPull, applied > 0 {
                await activityHandler?(.fetched(recordCount: applied))
            }
        }
        if unreadable + fromNewerBuild > 0 {
            // A newer build of Crest wrote some of these; the signal tells the
            // person why one device is missing something the others have.
            let skipped = BrowserCloudSyncActivity.skippedRecords(
                count: unreadable + fromNewerBuild,
                requiresAppUpdate: fromNewerBuild > 0
            )
            await activityHandler?(skipped)
        }

        // A record somebody deleted from iCloud is saved again; a later batch
        // drops the save of one the journal no longer holds.
        for deletion in event.deletions where deletion.recordID.zoneID == codec.recordZoneID {
            fields.remove(recordName: deletion.recordID.recordName)
            if codec.reference(for: deletion.recordID) != nil {
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
            }
        }
        try await record(&fields)
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        guard !transport.awaitsAccountDecision else { return }
        guard
            let deletion = event.deletions.first(where: {
                $0.zoneID == codec.recordZoneID
            })
        else { return }
        let loss = Self.loss(afterZoneDeletion: deletion.reason)
        try await send(ForgetCloudZone(loss: loss))
        if loss.restoresLocalRecords {
            syncEngine.state.add(pendingDatabaseChanges: [
                .saveZone(codec.recordZone)
            ])
            await enqueueLocalChanges(on: syncEngine)
        } else {
            // Somebody removed Crest's data from iCloud on purpose. Recreating
            // the zone and re-uploading every local record would undo that
            // before they finished reading the confirmation sheet. Local Spaces
            // stay untouched; the next deliberate start decides what to upload.
            await activityHandler?(.cloudDataRemoved)
        }
    }

    /// Why a zone stopped existing, as the core decides whether to rebuild it
    /// from local records. A reason this build cannot name reads as a
    /// deletion, which Crest does not overrule.
    static func loss(afterZoneDeletion reason: CKDatabase.DatabaseChange.Deletion.Reason) -> CloudZoneLoss {
        switch reason {
        case .encryptedDataReset: .encryptedDataReset
        case .purged: .purged
        case .deleted: .deleted
        @unknown default: .deleted
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async throws {
        var uploaded: [UploadedRecord] = []
        var fields = CloudFieldChanges()
        for record in event.savedRecords where record.recordID.zoneID == codec.recordZoneID {
            fields.update(with: record)
            if let saved = codec.uploadedRecord(record) { uploaded.append(saved) }
        }
        if !uploaded.isEmpty {
            try await deliver(AcknowledgeUploads(records: uploaded))
            if !transport.requiresFullPull {
                await activityHandler?(.uploaded(recordCount: uploaded.count))
            }
        }

        for failure in event.failedRecordSaves {
            let recordID = failure.record.recordID
            guard recordID.zoneID == codec.recordZoneID else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.serverRecord {
                    fields.update(with: serverRecord)
                    if transport.overwritesCloud {
                        syncEngine.state.add(
                            pendingRecordZoneChanges: [.saveRecord(recordID)]
                        )
                        continue
                    }
                    // The server copy cannot be applied here when this build
                    // cannot read it, usually a newer schema. Leaving the local
                    // save pending retries the same conflict forever and poisons
                    // every atomic batch it rides in; yield until the app can
                    // read it.
                    let merged = codec.syncRecord(from: serverRecord)
                    // The refreshed fields are kept before the merge, which
                    // may fail.
                    try await record(&fields)
                    let skipped: SyncRecordsSkipped? =
                        if let merged { try await mergeDownloadedRecords([merged]) } else {
                            SyncRecordsSkipped(unreadable: 1, fromNewerBuild: 0)
                        }
                    if let skipped, skipped.unreadable + skipped.fromNewerBuild > 0 {
                        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                        await activityHandler?(
                            .skippedRecords(count: 1, requiresAppUpdate: skipped.fromNewerBuild > 0))
                        continue
                    }
                    // CloudKit requires the server copy's change tag as the
                    // retry base. The journal deterministically reconciles the
                    // semantic values, then the refreshed system fields let the
                    // next save target that server version.
                    await enqueueLocalChanges(on: syncEngine)
                }
            case .zoneNotFound:
                fields.remove(recordName: recordID.recordName)
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(codec.recordZone)
                ])
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .unknownItem:
                fields.remove(recordName: recordID.recordName)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .networkFailure,
                .networkUnavailable,
                .zoneBusy,
                .serviceUnavailable,
                .notAuthenticated,
                .operationCancelled:
                break
            default:
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }
        try await record(&fields)
        // The overwrite ends once everything this device staged uploaded.
        if transport.overwritesCloud { try await send(SettleCloudOverwrite()) }
    }

    /// Whether the account change pauses sync until the person decides which
    /// copy to keep, as the core decides.
    private func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange
    ) async throws -> Bool {
        let transition: CloudAccountTransition =
            switch event.changeType {
            case .switchAccounts: .switchAccounts
            case .signOut: .signOut
            case .signIn: .signIn
            @unknown default: .unknown
            }
        let observed = try await send(ObserveCloudAccountChange(transition: transition))
        guard observed.awaitsAccountDecision else { return false }
        status = .pausedForAccountConfirmation
        return true
    }

    private func updateStatus(_ newStatus: BrowserCloudSyncStatus) async {
        status = newStatus
        await statusHandler?(newStatus)
    }
}

/// The server fields a CloudKit event changed, collected to keep in one
/// intent: each record's newest, and the records whose fields went.
struct CloudFieldChanges {
    // MARK: - Variables

    private(set) var updated: [String: CloudRecordFields] = [:]
    private(set) var removed: Set<String> = []

    var isEmpty: Bool { updated.isEmpty && removed.isEmpty }

    // MARK: - Actions - Changes

    mutating func update(with record: CKRecord) {
        let fields = CloudRecordFields(record: record)
        removed.remove(fields.recordName)
        updated[fields.recordName] = fields
    }

    mutating func remove(recordName: String) {
        updated.removeValue(forKey: recordName)
        removed.insert(recordName)
    }
}
