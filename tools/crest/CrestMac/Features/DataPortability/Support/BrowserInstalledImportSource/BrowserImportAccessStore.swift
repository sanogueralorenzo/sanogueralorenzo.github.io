import Foundation

enum BrowserImportAccessStore {
    private static let bookmarkKeyPrefix = "browser.import.access."

    static func bookmarkData(
        for application: ImportSource,
        defaults: UserDefaults? = nil
    ) -> Data? {
        guard let defaults = launchDefaults(defaults) else { return nil }
        return defaults.data(forKey: bookmarkKey(for: application))
    }

    static func saveBookmarkData(
        _ data: Data,
        for application: ImportSource,
        defaults: UserDefaults? = nil
    ) {
        guard let defaults = launchDefaults(defaults) else { return }
        defaults.set(data, forKey: bookmarkKey(for: application))
    }

    static func remember(
        _ directoryURL: URL,
        for application: ImportSource,
        defaults: UserDefaults? = nil
    ) throws {
        guard let defaults = launchDefaults(defaults) else { return }
        let data = try directoryURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        saveBookmarkData(data, for: application, defaults: defaults)
    }

    static func resolve(
        for application: ImportSource,
        defaults: UserDefaults? = nil
    ) -> BrowserImportDataDirectoryAccess? {
        guard let data = bookmarkData(for: application, defaults: defaults) else {
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try? remember(url, for: application, defaults: defaults)
            }
            return BrowserImportDataDirectoryAccess(url: url)
        } catch {
            clear(for: application, defaults: defaults)
            return nil
        }
    }

    static func clear(
        for application: ImportSource,
        defaults: UserDefaults? = nil
    ) {
        guard let defaults = launchDefaults(defaults) else { return }
        defaults.removeObject(forKey: bookmarkKey(for: application))
    }

    private static func bookmarkKey(
        for application: ImportSource
    ) -> String {
        bookmarkKeyPrefix + application.name
    }

    private static func launchDefaults(
        _ explicitDefaults: UserDefaults?
    ) -> UserDefaults? {
        if let explicitDefaults { return explicitDefaults }
        guard !BrowserLaunchEnvironment.current.requiresIsolation else {
            return nil
        }
        return .standard
    }
}
