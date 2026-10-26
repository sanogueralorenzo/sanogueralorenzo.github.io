protocol BrowserSafeStorageSecretProviding: Sendable {
    func secret(for application: ImportSource) throws -> String
}
