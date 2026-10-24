struct LaunchScopedBrowserSafeStorage: BrowserSafeStorageSecretProviding {
    private let safeStorage: (any BrowserSafeStorageSecretProviding)?

    init(
        launchEnvironment: BrowserLaunchEnvironment = .current,
        systemStorage: () -> any BrowserSafeStorageSecretProviding = {
            SecurityBrowserSafeStorage()
        }
    ) {
        if launchEnvironment.requiresIsolation {
            safeStorage = nil
        } else {
            safeStorage = systemStorage()
        }
    }

    func secret(for application: ImportSource) throws -> String {
        guard let safeStorage else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        return try safeStorage.secret(for: application)
    }
}
