@MainActor
protocol BrowserInstalledImportSourceDiscovering {
    /// The listed browsers installed here, by their apps; none of their data
    /// is read.
    func installedSources() -> [BrowserInstalledImportSource]

    /// `source` with what its data folder holds, read now.
    func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource

    /// The other browsers built on Chromium installed here, found by looking
    /// for their data, which setup offers once the person scans.
    func unlistedSources() -> [BrowserInstalledImportSource]
}

extension BrowserInstalledImportSourceDiscovering {
    func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource { source }
    func unlistedSources() -> [BrowserInstalledImportSource] { [] }
}
