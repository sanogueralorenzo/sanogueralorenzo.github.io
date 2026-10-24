@MainActor
struct LiveBrowserOnboardingImportCommitter:
    BrowserOnboardingImportCommitting
{
    private let safeStorage: any BrowserSafeStorageSecretProviding

    init(
        safeStorage: any BrowserSafeStorageSecretProviding =
            LaunchScopedBrowserSafeStorage()
    ) {
        self.safeStorage = safeStorage
    }

    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        let directoryAccess = BrowserImportAccessStore.resolve(for: review.source)
        defer { directoryAccess?.stopAccessing() }

        let passwords = try await selectedPasswords(for: review, payload: payload)
        try Task.checkCancellation()
        return BrowserOnboardingPreparedImport(passwords: passwords)
    }

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        try browser.importReviewedSpaces()
        return await BrowserPasswordImportCommitter.commit(preparedImport.passwords, browser: browser)
    }

    /// The passwords the review brings, read only when it brings any.
    private func selectedPasswords(
        for review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> [BrowserImportedPassword] {
        guard let payload, review.includedPasswordCount > 0 else { return [] }
        return try await BrowserPasswordImportReader.read(
            from: payload.passwordStores,
            application: review.source,
            safeStorage: safeStorage
        )
    }
}
