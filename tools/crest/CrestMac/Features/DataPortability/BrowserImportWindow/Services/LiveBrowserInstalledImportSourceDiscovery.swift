@MainActor
struct LiveBrowserInstalledImportSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    func installedSources() -> [BrowserInstalledImportSource] {
        BrowserInstalledImportSourceDetector.installedSources()
    }

    func scanned(_ source: BrowserInstalledImportSource) -> BrowserInstalledImportSource {
        BrowserInstalledImportSourceDetector.scanned(source)
    }

    func unlistedSources() -> [BrowserInstalledImportSource] {
        BrowserInstalledImportSourceDetector.unlistedSources()
    }
}
