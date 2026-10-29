import Foundation
import SQLite3

/// Owns only permission rows in the existing session database. Other native
/// features and the remaining core can use separate SQLite connections.
final class PermissionSQLite {
    struct Failure: Error {
        let code: Int32
        var reason: StorageFailure {
            switch code & 0xff {
            case SQLITE_BUSY, SQLITE_LOCKED: .busy
            case SQLITE_READONLY: .readOnly
            case SQLITE_CORRUPT, SQLITE_NOTADB: .damaged
            case SQLITE_FULL: .diskFull
            default: .unavailable
            }
        }
    }
    private var handle: OpaquePointer?
    init(directory: URL) throws {
        let file = directory.appendingPathComponent("session.sqlite")
        let result = sqlite3_open_v2(
            file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            sqlite3_close_v2(handle)
            handle = nil
            throw Failure(code: result)
        }
        sqlite3_busy_timeout(handle, 2_000)
        try execute(
            "CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, modified_at REAL NOT NULL, position INTEGER NOT NULL)"
        )
    }
    deinit { sqlite3_close_v2(handle) }
    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw Failure(code: result) }
    }
    private func execute(_ sql: String) throws { try check(sqlite3_exec(handle, sql, nil, nil, nil)) }
    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var value: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &value, nil))
        guard let value else { throw Failure(code: SQLITE_ERROR) }
        defer { sqlite3_finalize(value) }
        return try body(value)
    }
    private func text(_ value: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(value, index) else { return "" }
        return String(
            decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(value, index))), as: UTF8.self)
    }
    private func bind(_ value: OpaquePointer, _ index: Int32, _ text: String?) throws {
        guard let text else {
            try check(sqlite3_bind_null(value, index))
            return
        }
        try text.utf8CString.withUnsafeBufferPointer { bytes in
            try check(
                sqlite3_bind_text(
                    value, index, bytes.baseAddress, Int32(bytes.count - 1),
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)))
        }
    }
    func read() throws -> [PermissionRecord] {
        try statement(
            "SELECT id, space, scheme, host, port, permission, detail, decision, modified_at FROM device_site_permission ORDER BY position"
        ) { value in
            var rows: [PermissionRecord] = []
            while true {
                let step = sqlite3_step(value)
                if step == SQLITE_DONE { return rows }
                guard step == SQLITE_ROW else { throw Failure(code: step) }
                guard let id = UUID(uuidString: text(value, 0)), let space = UUID(uuidString: text(value, 1)),
                    let permission = SitePermission.named(text(value, 5)),
                    let decision = SitePermissionDecision.named(text(value, 7))
                else { continue }
                rows.append(
                    PermissionRecord(
                        id: id, spaceID: space,
                        origin: SiteOrigin(
                            scheme: text(value, 2), host: text(value, 3), port: Int(sqlite3_column_int(value, 4))),
                        permission: permission,
                        detail: sqlite3_column_type(value, 6) == SQLITE_NULL ? nil : text(value, 6),
                        decision: decision, modifiedAt: sqlite3_column_double(value, 8)))
            }
        }
    }
    func hasAdopted() throws -> Bool {
        try statement("SELECT 1 FROM device_adoption WHERE name='site-permissions'") { value in
            let result = sqlite3_step(value)
            guard result == SQLITE_ROW || result == SQLITE_DONE else { throw Failure(code: result) }
            return result == SQLITE_ROW
        }
    }
    func save(_ records: [PermissionRecord], adopting: Bool = false) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM device_site_permission")
            try statement(
                "INSERT INTO device_site_permission(id, space, scheme, host, port, permission, detail, decision, modified_at, position) VALUES (?,?,?,?,?,?,?,?,?,?)"
            ) { value in
                for (position, record) in records.enumerated() {
                    sqlite3_reset(value)
                    sqlite3_clear_bindings(value)
                    try bind(value, 1, record.id.uuidString)
                    try bind(value, 2, record.spaceID.uuidString)
                    try bind(value, 3, record.origin.scheme)
                    try bind(value, 4, record.origin.host)
                    try check(sqlite3_bind_int(value, 5, Int32(record.origin.port)))
                    try bind(value, 6, record.permission.name)
                    try bind(value, 7, record.detail)
                    try bind(value, 8, record.decision.name)
                    try check(sqlite3_bind_double(value, 9, record.modifiedAt))
                    try check(sqlite3_bind_int64(value, 10, Int64(position)))
                    let result = sqlite3_step(value)
                    guard result == SQLITE_DONE else { throw Failure(code: result) }
                }
            }
            if adopting { try execute("INSERT OR IGNORE INTO device_adoption(name) VALUES ('site-permissions')") }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
