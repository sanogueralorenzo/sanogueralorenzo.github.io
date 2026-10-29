import Foundation
import SQLite3

/// A connection to the session file, shared by native feature table owners.
final class SQLiteConnection {
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
    }
    deinit { sqlite3_close_v2(handle) }
    func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw Failure(code: result) }
    }
    func execute(_ sql: String) throws { try check(sqlite3_exec(handle, sql, nil, nil, nil)) }
    func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var value: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &value, nil))
        guard let value else { throw Failure(code: SQLITE_ERROR) }
        defer { sqlite3_finalize(value) }
        return try body(value)
    }
    func text(_ value: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(value, index) else { return "" }
        return String(
            decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(value, index))), as: UTF8.self)
    }
    func bind(_ value: OpaquePointer, _ index: Int32, _ text: String?) throws {
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
}
