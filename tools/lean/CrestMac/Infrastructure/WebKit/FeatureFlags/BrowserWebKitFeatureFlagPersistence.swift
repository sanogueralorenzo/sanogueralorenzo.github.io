import Foundation

protocol BrowserWebKitFeatureFlagPersisting: AnyObject {
    func load() -> [String: BrowserWebKitFeatureFlagOverride]
    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride])
}

protocol BrowserInactiveSchedulingPolicyPersisting: AnyObject {
    func load() -> BrowserInactiveSchedulingPolicy
    func save(_ policy: BrowserInactiveSchedulingPolicy)
}

final class UserDefaultsBrowserInactiveSchedulingPolicyPersistence:
    BrowserInactiveSchedulingPolicyPersisting
{
    static let currentKey = "crest.webkit-inactive-scheduling-policy.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = currentKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> BrowserInactiveSchedulingPolicy {
        guard
            let rawValue = defaults.string(forKey: key),
            let policy = BrowserInactiveSchedulingPolicy(rawValue: rawValue)
        else {
            return .suspend
        }
        return policy
    }

    func save(_ policy: BrowserInactiveSchedulingPolicy) {
        defaults.set(policy.rawValue, forKey: key)
    }
}

final class InMemoryBrowserInactiveSchedulingPolicyPersistence:
    BrowserInactiveSchedulingPolicyPersisting
{
    private(set) var policy: BrowserInactiveSchedulingPolicy

    init(policy: BrowserInactiveSchedulingPolicy = .suspend) {
        self.policy = policy
    }

    func load() -> BrowserInactiveSchedulingPolicy {
        policy
    }

    func save(_ policy: BrowserInactiveSchedulingPolicy) {
        self.policy = policy
    }
}

final class UserDefaultsBrowserWebKitFeatureFlagPersistence:
    BrowserWebKitFeatureFlagPersisting
{
    static let currentKey = "crest.webkit-feature-flag-overrides.v1"
    // This preference has its own storage revision so a default-policy change
    // can invalidate its saved choice without resetting unrelated WebKit flags.
    static let pageRenderingStorageKey = "PreferPageRenderingUpdatesNear60FPSEnabled.v2"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = currentKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String: BrowserWebKitFeatureFlagOverride] {
        guard let storedValues = defaults.dictionary(forKey: key) else {
            return [:]
        }
        return storedValues.reduce(into: [:]) { result, entry in
            let pageRenderingKey = BrowserWebKitFeatureFlagStore.preferPageRenderingUpdatesNear60FPSKey
            // The rendering preference is read only from its versioned slot.
            guard entry.key != pageRenderingKey else { return }
            guard let rawValue = entry.value as? String,
                let override = BrowserWebKitFeatureFlagOverride(rawValue: rawValue)
            else { return }
            let featureKey = entry.key == Self.pageRenderingStorageKey ? pageRenderingKey : entry.key
            result[featureKey] = override
        }
    }

    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride]) {
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let storedValues = overrides.reduce(into: [String: String]()) { result, entry in
            let storageKey =
                entry.key == BrowserWebKitFeatureFlagStore.preferPageRenderingUpdatesNear60FPSKey
                ? Self.pageRenderingStorageKey : entry.key
            result[storageKey] = entry.value.rawValue
        }
        defaults.set(storedValues, forKey: key)
    }
}

final class InMemoryBrowserWebKitFeatureFlagPersistence:
    BrowserWebKitFeatureFlagPersisting
{
    private(set) var overrides: [String: BrowserWebKitFeatureFlagOverride]

    init(overrides: [String: BrowserWebKitFeatureFlagOverride] = [:]) {
        self.overrides = overrides
    }

    func load() -> [String: BrowserWebKitFeatureFlagOverride] {
        overrides
    }

    func save(_ overrides: [String: BrowserWebKitFeatureFlagOverride]) {
        self.overrides = overrides
    }
}
