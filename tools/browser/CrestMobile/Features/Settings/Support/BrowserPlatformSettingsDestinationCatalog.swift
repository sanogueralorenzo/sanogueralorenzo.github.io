/// Settings destinations whose implementations are available in the mobile shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.all.filter { !$0.isMacOnly }
}
