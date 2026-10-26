import Foundation

/// Reads an installed browser's data for review: the core reads its profiles'
/// bookmarks, sessions and installed extensions away from the main thread, and the password stores
/// are counted where the browser keeps passwords Crest imports.
struct LiveBrowserOnboardingImportReader: BrowserOnboardingImportReading {
    // MARK: - Static Variables

    /// The largest icon file a review shows.
    private static let maximumIconBytes = 1_024 * 1_024

    // MARK: - Variables

    let core: CrestCore

    func read(
        _ payload: BrowserDetectedImportPayload
    ) async throws -> BrowserOnboardingImportReadOutput {
        let passwordCandidates =
            payload.application.suppliesPasswords
            ? try await BrowserPasswordImportReader.candidates(
                from: payload.passwordStores,
                application: payload.application
            )
            : []
        try Task.checkCancellation()

        let query = ReadImport(source: payload.application, profiles: payload.profiles)
        let core = self.core
        let (imported, icons) = try await Task.detached(priority: .userInitiated) {
            let imported = try core.query(query)
            return (imported, Self.icons(of: imported.extensions))
        }.value
        try Task.checkCancellation()

        return BrowserOnboardingImportReadOutput(
            payload: payload,
            imported: imported.spaces,
            passwordCandidates: passwordCandidates,
            extensions: imported.extensions,
            extensionIcons: icons,
            leftOut: imported.leftOut
        )
    }

    // MARK: - Actions - Icons

    /// The icons `offers` name, read while the browser's folder is open to
    /// Crest. An icon that is missing or too large is left out.
    private static func icons(of offers: [ImportSpaceExtensions]) -> [String: Data] {
        var icons: [String: Data] = [:]
        for item in offers.flatMap(\.extensions) where icons[item.extensionID] == nil {
            guard let path = item.iconPath,
                let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                data.count <= maximumIconBytes
            else { continue }
            icons[item.extensionID] = data
        }
        return icons
    }
}
