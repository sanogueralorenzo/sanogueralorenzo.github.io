import Foundation
import SQLite3
import XCTest

@testable import Crest

/// A session the core keeps in its own file in a temporary directory, opened
/// the way a launch opens it, and read back the way the next launch would.
@MainActor
final class BrowserStoredSessionHarness {
    // MARK: - Types

    enum HarnessError: Error {
        case sqlite(Int32)
        case missingPart(String)
    }

    // MARK: - Variables

    let directory: URL
    let favicons: InMemoryBrowserFaviconStore
    let core: CrestCore
    let store: BrowserStore
    var url: URL { directory.appendingPathComponent("session.sqlite") }

    // MARK: - Initializers

    /// Gives a new file the session a core opens from `seed`, or without one
    /// the session a first launch starts with, as its first session, with the
    /// journal of a device that has staged nothing yet, `syncDeviceID` when
    /// named, then opens it with a window on its launch Space. The images
    /// `favicons` holds are the ones its tabs wear.
    convenience init(
        seed: SessionState.Seed?, syncDeviceID: UUID? = nil,
        favicons: InMemoryBrowserFaviconStore = InMemoryBrowserFaviconStore()
    ) throws {
        try self.init(
            seed: seed, journalData: syncDeviceID.map { StoredSyncJournal.fresh(deviceID: $0) }, favicons: favicons)
    }

    /// Gives a new file the session a core opens from `seed` and the journal
    /// `journalData` holds, which only the core reads, as its first session,
    /// then opens it as above.
    init(
        seed: SessionState.Seed?, journalData: Data?,
        favicons: InMemoryBrowserFaviconStore = InMemoryBrowserFaviconStore()
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.favicons = favicons
        core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        try BrowserInstalledRelease.adopt(seed, journalData: journalData, into: core)
        store = try Self.open(core, favicons: favicons)
    }

    /// A file of device `syncDeviceID` whose first session is the one a core
    /// opens from `seed`, opened as above, once its launch staged it: its
    /// journal holds every record of the session, none of them uploaded yet.
    static func staged(
        seed: SessionState.Seed, syncDeviceID: UUID = UUID(),
        favicons: InMemoryBrowserFaviconStore = InMemoryBrowserFaviconStore()
    ) async throws -> BrowserStoredSessionHarness {
        let harness = try BrowserStoredSessionHarness(seed: seed, syncDeviceID: syncDeviceID, favicons: favicons)
        await harness.core.settleSync()
        return harness
    }

    /// A file of device `syncDeviceID` whose first session is the one a core
    /// opens from `seed`, opened as above, once the cloud saved everything
    /// its launch staged: a device that has already uploaded the session.
    static func uploaded(
        seed: SessionState.Seed, syncDeviceID: UUID = UUID(),
        favicons: InMemoryBrowserFaviconStore = InMemoryBrowserFaviconStore()
    ) async throws -> BrowserStoredSessionHarness {
        let harness = try BrowserStoredSessionHarness(seed: seed, syncDeviceID: syncDeviceID, favicons: favicons)
        _ = try await harness.uploadPendingRecords()
        return harness
    }

    /// Opens the file a harness left behind, as a launch after a crash would.
    private init(copying directory: URL, favicons: InMemoryBrowserFaviconStore) throws {
        self.directory = directory
        self.favicons = favicons
        core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        store = try Self.open(core, favicons: favicons)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func open(_ core: CrestCore, favicons: InMemoryBrowserFaviconStore) throws -> BrowserStore {
        let stored = try BrowserCoreSessionAuthority.openStored(in: core, favicons: favicons)
        return BrowserStore.production(
            stored: stored, core: core, favicons: favicons, credentialVault: InMemoryCredentialVault())
    }

    // MARK: - Actions - Launches

    /// The file as the process would leave it if it stopped now, opened by a
    /// new launch. This harness keeps its own core and file.
    func relaunch() async throws -> BrowserStoredSessionHarness {
        await store.flushPendingSyncPersistence()
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try copyFile(to: copy)
        return try BrowserStoredSessionHarness(copying: copy, favicons: favicons)
    }

    /// Copies the file as it stands now into `copy`, a new directory.
    private func copyFile(to copy: URL) throws {
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.copyItem(
                atPath: url.path + suffix, toPath: copy.appendingPathComponent(url.lastPathComponent).path + suffix)
        }
    }

    // MARK: - Actions - Reading the file

    /// The session the file holds now, as the next launch opens it, and its
    /// journal. The session is read from a copy of the file, so this harness
    /// keeps its own. The read model keeps no disposable seed's marker, so,
    /// like `BrowserStore.sessionSeed`, the session carries none.
    func stored() throws -> (session: SessionState.Seed, journal: StoredSyncJournal?) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: copy) }
        try copyFile(to: copy)
        let reader = try CrestCore(configuration: AppConfiguration(storageDirectory: copy.path))
        var session: SessionState?
        for case .workspaceOpened(let opened) in try reader.send(OpenWorkspace(kind: .persistent, seed: nil)) {
            session = opened.session
        }
        var seed = try XCTUnwrap(session).seed
        seed.disposableSeedMarker = nil
        let journal = try withConnection { try Self.read("journal", in: $0) }.map(StoredSyncJournal.init)
        return (seed, journal)
    }

    /// One stored part's bytes, exactly as the file holds them.
    func storedPart(_ part: String) throws -> Data? {
        try withConnection { try Self.read(part, in: $0) }
    }

    /// The sync journal the file holds, which is the one the core accepted
    /// last, since the core saves each journal before it accepts it.
    func storedJournal() throws -> StoredSyncJournal {
        try Self.storedJournal(in: directory)
    }

    /// The sync journal the session file in `directory` holds.
    static func storedJournal(in directory: URL) throws -> StoredSyncJournal {
        let url = directory.appendingPathComponent("session.sqlite")
        let data = try withConnection(at: url, writable: false) { try read("journal", in: $0) }
        return try StoredSyncJournal(try XCTUnwrap(data))
    }

    // MARK: - Actions - Cloud sync

    /// Sends `intent` to the core as the cloud transport does, from another
    /// thread, and returns once the drain that brought what it changed and
    /// the notice of its delivery have run on the main queue.
    func deliver(_ intent: some CloudSyncIntent) async throws {
        let core = core
        try await Task.detached { _ = try core.deliver(intent) }.value
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    /// Sends `intent` to the core on the main thread, which a test may do,
    /// and applies what it changed at once.
    func deliverNow(_ intent: some CloudSyncIntent) throws {
        try core.deliver(intent)
        core.drain()
    }

    /// Every record that waits to upload once the stages queued so far
    /// settled, as the transport uploads them.
    func pendingRecords() async throws -> [SyncRecord] {
        await core.settleSync()
        return try core.query(RecordsToUpload(records: try core.query(PendingUploads()).records)).records
    }

    /// Uploads every record that waits to upload, as `pendingRecords()` reads
    /// them, and acknowledges them as the transport does once the cloud saved
    /// them. Answers what the cloud now holds of them.
    func uploadPendingRecords() async throws -> [SyncRecord] {
        let records = try await pendingRecords()
        try deliverNow(
            AcknowledgeUploads(
                records: records.map {
                    UploadedRecord(record: SyncRecordReference(kind: $0.kind, id: $0.id), version: $0.version)
                }))
        return records
    }

    /// Every record the journal holds that the transport would send, once the
    /// stages queued so far settled.
    func heldRecords() async throws -> [SyncRecord] {
        await core.settleSync()
        return try core.query(RecordsToUpload(records: try storedJournal().records.map(\.reference))).records
    }

    /// A second device that took everything this device's journal holds from
    /// the cloud onto a fresh install, as a device joining the same iCloud
    /// does.
    func joiningDevice() async throws -> BrowserStoredSessionHarness {
        let other = try BrowserStoredSessionHarness(seed: nil)
        try other.deliverNow(ReplaceSeedWithCloudRecords(records: try await heldRecords()))
        return other
    }

    /// Acknowledges every record waiting to upload, at the version the journal
    /// holds it at, as the transport does once the cloud saved them.
    func acknowledgePendingUploads() throws {
        let pending = try core.query(PendingUploads()).records
        let records = try core.query(RecordsToUpload(records: pending)).records
        try deliverNow(
            AcknowledgeUploads(
                records: records.map {
                    UploadedRecord(record: SyncRecordReference(kind: $0.kind, id: $0.id), version: $0.version)
                }))
    }

    /// Whether the journal the file holds is the one the core last told the
    /// app about: as many records, as many of them waiting to upload.
    func storedJournalIsPublished() throws -> Bool {
        let stored = try storedJournal()
        return core.state.syncJournal?.records == stored.records.count
            && core.state.syncJournal?.pendingRecords == stored.pending.count
    }

    /// The Space the device table the file holds records `window` showing,
    /// or nil when it keeps no record of that window.
    func storedShownSpace(of window: UUID) throws -> UUID? {
        try withConnection { connection in
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(
                connection, "SELECT shown_space FROM device_window WHERE id=?", -1, &statement, nil)
            guard prepared == SQLITE_OK, let statement else { throw HarnessError.sqlite(prepared) }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(
                statement, 1, window.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let shown = sqlite3_column_text(statement, 0) else {
                throw HarnessError.sqlite(result)
            }
            return UUID(uuidString: String(cString: shown))
        }
    }

    // MARK: - Actions - Faults

    /// Makes the file refuse every write to `part`, as a full disk or a failing
    /// device refuses one in the middle of a transaction.
    func refuseWrites(to part: String) throws {
        try withConnection(writable: true) { connection in
            for operation in ["INSERT", "UPDATE"] {
                try Self.execute(
                    "CREATE TRIGGER refuse_\(operation) BEFORE \(operation) ON checkpoint WHEN NEW.part = '\(part)' "
                        + "BEGIN SELECT RAISE(ABORT, 'refused'); END", in: connection)
            }
        }
    }

    func acceptWrites() throws {
        try withConnection(writable: true) { connection in
            try Self.execute("DROP TRIGGER refuse_INSERT", in: connection)
            try Self.execute("DROP TRIGGER refuse_UPDATE", in: connection)
        }
    }

    // MARK: - Actions - SQLite

    private func withConnection<T>(writable: Bool = false, _ body: (OpaquePointer) throws -> T) throws -> T {
        try Self.withConnection(at: url, writable: writable, body)
    }

    private static func withConnection<T>(at url: URL, writable: Bool, _ body: (OpaquePointer) throws -> T) throws -> T
    {
        var connection: OpaquePointer?
        let flags = writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        let opened = sqlite3_open_v2(url.path, &connection, flags, nil)
        guard opened == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw HarnessError.sqlite(opened)
        }
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection, 2000)
        return try body(connection)
    }

    private static func execute(_ sql: String, in connection: OpaquePointer) throws {
        let result = sqlite3_exec(connection, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw HarnessError.sqlite(result) }
    }

    /// Every stored part the session file in `directory` holds, by part.
    static func parts(in directory: URL) throws -> [String: Data] {
        let url = directory.appendingPathComponent("session.sqlite")
        return try withConnection(at: url, writable: false) { connection in
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(connection, "SELECT part, data FROM checkpoint", -1, &statement, nil)
            guard prepared == SQLITE_OK, let statement else { throw HarnessError.sqlite(prepared) }
            defer { sqlite3_finalize(statement) }
            var parts: [String: Data] = [:]
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return parts }
                guard result == SQLITE_ROW, let part = sqlite3_column_text(statement, 0) else {
                    throw HarnessError.sqlite(result)
                }
                let bytes = sqlite3_column_blob(statement, 1)
                parts[String(cString: part)] =
                    bytes.map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 1))) } ?? Data()
            }
        }
    }

    private static func read(_ part: String, in connection: OpaquePointer) throws -> Data? {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(connection, "SELECT data FROM checkpoint WHERE part=?", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw HarnessError.sqlite(prepared) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, part, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw HarnessError.sqlite(result)
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
