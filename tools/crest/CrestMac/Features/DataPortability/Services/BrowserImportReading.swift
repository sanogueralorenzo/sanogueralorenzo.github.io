protocol BrowserImportReading: Sendable {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserImportReadOutput
}
