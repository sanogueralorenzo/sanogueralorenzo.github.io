import Foundation

@MainActor
struct BrowserOnboardingPreviewDataAccessProvider:
    BrowserOnboardingDataAccessProviding
{
    func resolve(
        for application: ImportSource
    ) -> BrowserImportDataDirectoryAccess? {
        nil
    }

    func clear(for application: ImportSource) {}

    func remember(
        _ directoryURL: URL,
        for application: ImportSource
    ) throws {}

    func chooseDataFolder(
        for application: ImportSource,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        completion(nil)
    }

    func hasSavedAccess(for application: ImportSource) -> Bool {
        false
    }
}

@MainActor
struct BrowserOnboardingPreviewImportCommitter:
    BrowserOnboardingImportCommitting
{
    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport {
        throw CancellationError()
    }

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult {
        throw CancellationError()
    }
}

struct BrowserOnboardingPreviewImportReader: BrowserOnboardingImportReading {
    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        throw CancellationError()
    }
}

@MainActor
struct BrowserOnboardingPreviewSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}
