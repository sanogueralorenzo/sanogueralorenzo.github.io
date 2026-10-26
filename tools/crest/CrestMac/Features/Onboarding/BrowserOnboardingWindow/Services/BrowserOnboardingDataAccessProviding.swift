import Foundation

@MainActor
protocol BrowserOnboardingDataAccessProviding {
    func resolve(
        for application: ImportSource
    ) -> BrowserImportDataDirectoryAccess?

    func clear(for application: ImportSource)

    func remember(
        _ directoryURL: URL,
        for application: ImportSource
    ) throws

    func chooseDataFolder(
        for application: ImportSource,
        completion: @escaping @MainActor (URL?) -> Void
    )

    func hasSavedAccess(for application: ImportSource) -> Bool
}
