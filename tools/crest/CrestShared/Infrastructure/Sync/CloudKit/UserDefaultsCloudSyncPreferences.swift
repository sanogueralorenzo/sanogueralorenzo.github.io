import Foundation

@MainActor
final class UserDefaultsBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    static let defaultEnabledKey = "crest.cloud-sync.enabled"

    private let defaults: UserDefaults
    private let enabledKey: String

    init(
        defaults: UserDefaults = .standard,
        enabledKey: String = defaultEnabledKey
    ) {
        self.defaults = defaults
        self.enabledKey = enabledKey
    }

    func loadIsEnabled() -> Bool? {
        guard defaults.object(forKey: enabledKey) != nil else { return nil }
        return defaults.bool(forKey: enabledKey)
    }

    func saveIsEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: enabledKey)
    }
}
