/// The Mac has no system Passwords write-through; WebKit and the system manage
/// that integration directly.
@MainActor
enum BrowserSystemPasswordWriteThroughSystem {
    /// This launch's platform facts for the core's write-through rule.
    static func facts(
        for launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> SystemPasswordWriteThrough {
        SystemPasswordWriteThrough(
            isMobilePlatform: false,
            supportsSystemPasswordSaving: false,
            hasManagedBrowserCapability: false,
            isLaunchIsolated: launchEnvironment.requiresIsolation
        )
    }
}
