import Foundation
import SQLite3
import XCTest

@testable import Crest

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class BrowserInstalledImportSourceTests: XCTestCase {
    func testIsolatedLaunchRejectsSafeStorageBeforeKeychainAccess() {
        XCTAssertThrowsError(
            try LaunchScopedBrowserSafeStorage().secret(for: .chrome)
        ) { error in
            XCTAssertEqual(
                error as? BrowserPasswordImportError,
                .safeStorageUnavailable
            )
        }
    }

    func testRememberedBrowserAccessIsStoredSeparatelyForEachBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)

        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults),
            arcBookmark
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .chrome, defaults: defaults)
        )
    }

    func testClearingRememberedAccessOnlyClearsTheRequestedBrowser() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arcBookmark = Data("arc-bookmark".utf8)
        let zenBookmark = Data("zen-bookmark".utf8)
        BrowserImportAccessStore.saveBookmarkData(
            arcBookmark,
            for: .arc,
            defaults: defaults
        )
        BrowserImportAccessStore.saveBookmarkData(
            zenBookmark,
            for: .zen,
            defaults: defaults
        )

        BrowserImportAccessStore.clear(for: .arc, defaults: defaults)

        XCTAssertNil(
            BrowserImportAccessStore.bookmarkData(for: .arc, defaults: defaults)
        )
        XCTAssertEqual(
            BrowserImportAccessStore.bookmarkData(for: .zen, defaults: defaults),
            zenBookmark
        )
    }

    func testRememberedDataDirectoryResolvesForARepeatImport() throws {
        let suite = "BrowserInstalledImportSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: directory) }

        try BrowserImportAccessStore.remember(
            directory,
            for: .arc,
            defaults: defaults
        )
        let access = try XCTUnwrap(
            BrowserImportAccessStore.resolve(for: .arc, defaults: defaults)
        )
        defer { access.stopAccessing() }

        XCTAssertEqual(
            access.url.resolvingSymlinksInPath(),
            directory.resolvingSymlinksInPath()
        )
    }

    func testHostHomeResolutionPrefersTheAccountHomeOverASandboxContainer() {
        let containerHome = URL(fileURLWithPath: "/Users/test/Library/Containers/app/Data")
        let accountHome = URL(fileURLWithPath: "/Users/test")

        XCTAssertEqual(
            ImportSource.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: accountHome
            ),
            accountHome
        )
        XCTAssertEqual(
            ImportSource.resolvedHomeDirectory(
                currentHome: containerHome,
                accountHome: nil
            ),
            containerHome
        )
    }

    func testChromiumPasswordReaderCountsAndDecryptsSupportedLogins() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let databaseURL = home.appendingPathComponent("Login Data")
        try createLoginDatabase(
            at: databaseURL,
            encryptedPassword: Data([0x76, 0x31, 0x30])
                + Data(hex: "13aaf27b4bd1b4ad2dbdea76e9ff6575")
        )
        let store = ImportPasswordStore(
            id: "Profile 1",
            profileName: "Personal",
            path: databaseURL.path
        )

        let count = try await BrowserPasswordImportReader.count(in: [store])
        XCTAssertEqual(count, 1)

        let candidates = try await BrowserPasswordImportReader.candidates(
            from: [store],
            application: .arc
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].origin.description, "https://accounts.example.com")
        XCTAssertEqual(candidates[0].sourceProfileName, "Personal")

        let passwords = try await BrowserPasswordImportReader.read(
            from: [store],
            application: .arc,
            safeStorage: StubSafeStorage(secret: "test-safe-storage")
        )

        let password = try XCTUnwrap(passwords.first)
        XCTAssertEqual(passwords.count, 1)
        XCTAssertEqual(password.origin.description, "https://accounts.example.com")
        XCTAssertEqual(password.username, "paul@example.com")
        XCTAssertEqual(password.password, "hunter2")
        XCTAssertFalse(password.description.contains("hunter2"))
    }

    func testChromiumPasswordReaderPreservesStoreOrderAndV11Support() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let ciphertext = Data(hex: "13aaf27b4bd1b4ad2dbdea76e9ff6575")
        let defaultDatabaseURL = home.appendingPathComponent("Default/Login Data")
        let secondaryDatabaseURL = home.appendingPathComponent("Profile 1/Login Data")
        try createLoginDatabase(
            at: defaultDatabaseURL,
            encryptedPassword: Data("v10".utf8) + ciphertext
        )
        try createLoginDatabase(
            at: secondaryDatabaseURL,
            encryptedPassword: Data("v11".utf8) + ciphertext
        )
        let stores = [
            ImportPasswordStore(
                id: "Default",
                profileName: "Personal",
                path: defaultDatabaseURL.path
            ),
            ImportPasswordStore(
                id: "Profile 1",
                profileName: "Work",
                path: secondaryDatabaseURL.path
            ),
        ]

        let candidates = try await BrowserPasswordImportReader.candidates(
            from: stores,
            application: .chrome
        )
        let passwords = try await BrowserPasswordImportReader.read(
            from: stores,
            application: .chrome,
            safeStorage: StubSafeStorage(secret: "test-safe-storage")
        )

        XCTAssertEqual(candidates.map(\.sourceProfileID), ["Default", "Profile 1"])
        XCTAssertEqual(candidates.map(\.sourceProfileName), ["Personal", "Work"])
        XCTAssertEqual(passwords.map(\.sourceProfileID), ["Default", "Profile 1"])
        XCTAssertEqual(passwords.map(\.password), ["hunter2", "hunter2"])
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-import-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func createLoginDatabase(
        at url: URL,
        encryptedPassword: Data
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let handle = try XCTUnwrap(database)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(
            sqlite3_exec(
                handle,
                "CREATE TABLE logins (origin_url TEXT, username_value TEXT, password_value BLOB, blacklisted_by_user INTEGER);",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                handle,
                "INSERT INTO logins VALUES (?, ?, ?, 0);",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        let insert = try XCTUnwrap(statement)
        defer { sqlite3_finalize(insert) }
        sqlite3_bind_text(insert, 1, "https://accounts.example.com/login", -1, sqliteTransient)
        sqlite3_bind_text(insert, 2, "paul@example.com", -1, sqliteTransient)
        _ = encryptedPassword.withUnsafeBytes { bytes in
            sqlite3_bind_blob(insert, 3, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        XCTAssertEqual(sqlite3_step(insert), SQLITE_DONE)
    }
}

private struct StubSafeStorage: BrowserSafeStorageSecretProviding {
    let secret: String

    func secret(for application: ImportSource) throws -> String {
        secret
    }
}

extension Data {
    fileprivate init(hex: String) {
        self.init(
            stride(from: 0, to: hex.count, by: 2).compactMap { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return UInt8(hex[start..<end], radix: 16)
            })
    }
}
