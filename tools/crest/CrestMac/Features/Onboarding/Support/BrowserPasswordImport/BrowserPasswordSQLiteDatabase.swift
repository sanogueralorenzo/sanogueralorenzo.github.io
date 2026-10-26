import Foundation
import SQLite3

final class BrowserPasswordSQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true,
            values?.fileSize ?? 0 <= BrowserPasswordImportReader.maximumDatabaseByteCount
        else {
            throw BrowserPasswordImportError.unreadableDatabase
        }
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw BrowserPasswordImportError.unreadableDatabase
        }
        handle = database
        sqlite3_busy_timeout(database, 1_000)
        sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA trusted_schema = OFF", nil, nil, nil)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, 16 * 1_024 * 1_024)
        sqlite3_limit(database, SQLITE_LIMIT_SQL_LENGTH, 64 * 1_024)
        sqlite3_limit(database, SQLITE_LIMIT_COLUMN, 64)
        sqlite3_limit(database, SQLITE_LIMIT_ATTACHED, 0)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func encryptedRecords(limit: Int) throws -> [BrowserEncryptedPasswordRecord] {
        guard limit > 0, let handle else { return [] }
        let sql = """
            SELECT origin_url, username_value, password_value
            FROM logins
            WHERE blacklisted_by_user = 0
              AND username_value <> ''
              AND length(password_value) > 3
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else {
            throw BrowserPasswordImportError.unreadableDatabase
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(min(limit, Int(Int32.max))))

        var records: [BrowserEncryptedPasswordRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW else {
                throw BrowserPasswordImportError.unreadableDatabase
            }
            guard let urlString = string(statement, column: 0),
                let url = URL(string: urlString),
                let origin = CredentialOrigin(url: url),
                origin.isSecure,
                let username = string(statement, column: 1),
                let encryptedPassword = data(statement, column: 2),
                encryptedPassword.prefix(3) == Data("v10".utf8)
                    || encryptedPassword.prefix(3) == Data("v11".utf8)
            else {
                continue
            }
            records.append(
                BrowserEncryptedPasswordRecord(
                    origin: origin,
                    username: username,
                    encryptedPassword: encryptedPassword
                ))
        }
    }

    private func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count >= 0, count <= 1_048_576 else { return nil }
        return String(
            decoding: UnsafeBufferPointer(start: bytes, count: count),
            as: UTF8.self
        )
    }

    private func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 16 * 1_024 * 1_024,
            let bytes = sqlite3_column_blob(statement, column)
        else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
