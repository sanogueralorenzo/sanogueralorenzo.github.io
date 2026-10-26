/// Settings destinations whose implementations are available in the mobile shell.
enum BrowserPlatformSettingsDestinationCatalog {
    /// The destinations whose subject exists only on the Mac: the engine
    /// choice, rebindable keyboard commands, WebKit's private feature registry
    /// and the agents server.
    static let macOnly: Set<BrowserSettingsDestination> = [.engines, .shortcuts, .featureFlags, .agents]

    static let cases = BrowserSettingsDestination.all.filter { !macOnly.contains($0) }
}
