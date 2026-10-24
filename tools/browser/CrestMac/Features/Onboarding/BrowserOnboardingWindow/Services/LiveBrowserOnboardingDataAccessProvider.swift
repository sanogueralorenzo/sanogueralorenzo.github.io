import Foundation

@MainActor
struct LiveBrowserOnboardingDataAccessProvider:
    BrowserOnboardingDataAccessProviding
{
    func resolve(
        for application: ImportSource
    ) -> BrowserImportDataDirectoryAccess? {
        BrowserImportAccessStore.resolve(for: application)
    }

    func clear(for application: ImportSource) {
        BrowserImportAccessStore.clear(for: application)
    }

    func remember(
        _ directoryURL: URL,
        for application: ImportSource
    ) throws {
        try BrowserImportAccessStore.remember(
            directoryURL,
            for: application
        )
    }

    func chooseDataFolder(
        for application: ImportSource,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        BrowserImportFilePicker.chooseDataFolder(
            for: application,
            completion: completion
        )
    }

    func hasSavedAccess(for application: ImportSource) -> Bool {
        BrowserImportAccessStore.bookmarkData(for: application) != nil
    }
}
