import Foundation
import SQLite3

/// Owns only permission rows in the session database.
final class PermissionSQLite {
    private let db: SQLiteConnection
    init(directory: URL) throws {
        db = try SQLiteConnection(directory: directory)
        try db.execute(
            "CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, modified_at REAL NOT NULL, position INTEGER NOT NULL)"
        )
    }
    func read() throws -> [PermissionRecord] {
        try db.statement(
            "SELECT id, space, scheme, host, port, permission, detail, decision, modified_at FROM device_site_permission ORDER BY position"
        ) { value in
            var rows: [PermissionRecord] = []
            while true {
                let step = sqlite3_step(value)
                if step == SQLITE_DONE { return rows }
                guard step == SQLITE_ROW else { throw SQLiteConnection.Failure(code: step) }
                guard let id = UUID(uuidString: db.text(value, 0)), let space = UUID(uuidString: db.text(value, 1)),
                    let permission = SitePermission.named(db.text(value, 5)),
                    let decision = SitePermissionDecision.named(db.text(value, 7))
                else { continue }
                rows.append(
                    PermissionRecord(
                        id: id, spaceID: space,
                        origin: SiteOrigin(
                            scheme: db.text(value, 2), host: db.text(value, 3), port: Int(sqlite3_column_int(value, 4))),
                        permission: permission,
                        detail: sqlite3_column_type(value, 6) == SQLITE_NULL ? nil : db.text(value, 6),
                        decision: decision, modifiedAt: sqlite3_column_double(value, 8)))
            }
        }
    }
    func hasAdopted() throws -> Bool {
        try db.statement("SELECT 1 FROM device_adoption WHERE name='site-permissions'") { value in
            let result = sqlite3_step(value)
            guard result == SQLITE_ROW || result == SQLITE_DONE else { throw SQLiteConnection.Failure(code: result) }
            return result == SQLITE_ROW
        }
    }
    func save(_ records: [PermissionRecord], adopting: Bool = false) throws {
        try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("DELETE FROM device_site_permission")
            try db.statement(
                "INSERT INTO device_site_permission(id, space, scheme, host, port, permission, detail, decision, modified_at, position) VALUES (?,?,?,?,?,?,?,?,?,?)"
            ) { value in
                for (position, record) in records.enumerated() {
                    sqlite3_reset(value)
                    sqlite3_clear_bindings(value)
                    try db.bind(value, 1, record.id.uuidString)
                    try db.bind(value, 2, record.spaceID.uuidString)
                    try db.bind(value, 3, record.origin.scheme)
                    try db.bind(value, 4, record.origin.host)
                    try db.check(sqlite3_bind_int(value, 5, Int32(record.origin.port)))
                    try db.bind(value, 6, record.permission.name)
                    try db.bind(value, 7, record.detail)
                    try db.bind(value, 8, record.decision.name)
                    try db.check(sqlite3_bind_double(value, 9, record.modifiedAt))
                    try db.check(sqlite3_bind_int64(value, 10, Int64(position)))
                    let result = sqlite3_step(value)
                    guard result == SQLITE_DONE else { throw SQLiteConnection.Failure(code: result) }
                }
            }
            if adopting { try db.execute("INSERT OR IGNORE INTO device_adoption(name) VALUES ('site-permissions')") }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }
}
