import Foundation

enum BrowserPasswordImportReader {
    static let maximumDatabaseByteCount = 512 * 1_024 * 1_024
    private static let maximumPasswordCount = 100_000

    static func count(
        in stores: [ImportPasswordStore]
    ) async throws -> Int {
        try await Task.detached(priority: .utility) {
            var total = 0
            var readableStoreCount = 0
            for store in stores where total < maximumPasswordCount {
                guard
                    let records = try? BrowserPasswordSQLiteDatabase(
                        url: URL(fileURLWithPath: store.path)
                    ).encryptedRecords(limit: maximumPasswordCount - total)
                else {
                    continue
                }
                readableStoreCount += 1
                total += records.count
            }
            if !stores.isEmpty, readableStoreCount == 0 {
                throw BrowserPasswordImportError.unreadableDatabase
            }
            return total
        }.value
    }

    static func read(
        from stores: [ImportPasswordStore],
        application: ImportSource,
        safeStorage: any BrowserSafeStorageSecretProviding
    ) async throws -> [BrowserImportedPassword] {
        guard application.suppliesPasswords else {
            throw BrowserPasswordImportError.unsupportedBrowser
        }
        guard !stores.isEmpty else { return [] }
        let secret = try safeStorage.secret(for: application)
        return try await Task.detached(priority: .userInitiated) {
            let key = try ChromiumPasswordCrypto.key(safeStorageSecret: secret)
            var imported: [BrowserImportedPassword] = []
            var readableStoreCount = 0
            imported.reserveCapacity(min(maximumPasswordCount, stores.count * 100))
            for store in stores where imported.count < maximumPasswordCount {
                guard
                    let records = try? BrowserPasswordSQLiteDatabase(url: URL(fileURLWithPath: store.path))
                        .encryptedRecords(limit: maximumPasswordCount - imported.count)
                else {
                    continue
                }
                readableStoreCount += 1
                for record in records {
                    guard
                        let decrypted = try? ChromiumPasswordCrypto.decrypt(
                            record.encryptedPassword,
                            key: key
                        ),
                        let password = String(data: decrypted, encoding: .utf8),
                        !password.isEmpty
                    else { continue }
                    imported.append(
                        BrowserImportedPassword(
                            sourceApplication: application,
                            sourceProfileID: store.id,
                            sourceProfileName: store.profileName,
                            origin: record.origin,
                            username: record.username,
                            password: password
                        ))
                }
            }
            if readableStoreCount == 0 {
                throw BrowserPasswordImportError.unreadableDatabase
            }
            return imported
        }.value
    }

    static func candidates(
        from stores: [ImportPasswordStore],
        application: ImportSource
    ) async throws -> [BrowserPasswordImportCandidate] {
        guard application.suppliesPasswords else {
            throw BrowserPasswordImportError.unsupportedBrowser
        }
        guard !stores.isEmpty else { return [] }
        return try await Task.detached(priority: .utility) {
            var candidates: [BrowserPasswordImportCandidate] = []
            var readableStoreCount = 0
            candidates.reserveCapacity(min(maximumPasswordCount, stores.count * 100))
            for store in stores where candidates.count < maximumPasswordCount {
                guard
                    let records = try? BrowserPasswordSQLiteDatabase(url: URL(fileURLWithPath: store.path))
                        .encryptedRecords(limit: maximumPasswordCount - candidates.count)
                else {
                    continue
                }
                readableStoreCount += 1
                candidates.append(
                    contentsOf: records.map { record in
                        BrowserPasswordImportCandidate(
                            sourceApplication: application,
                            sourceProfileID: store.id,
                            sourceProfileName: store.profileName,
                            origin: record.origin
                        )
                    })
            }
            if readableStoreCount == 0 {
                throw BrowserPasswordImportError.unreadableDatabase
            }
            return candidates
        }.value
    }
}
