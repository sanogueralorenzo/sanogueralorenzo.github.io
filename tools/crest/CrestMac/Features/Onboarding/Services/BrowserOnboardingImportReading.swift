protocol BrowserOnboardingImportReading: Sendable {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput
}
