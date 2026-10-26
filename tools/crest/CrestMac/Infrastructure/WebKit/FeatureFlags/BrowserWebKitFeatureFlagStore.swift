import Observation
import WebKit

enum BrowserInactiveSchedulingPolicy: String, CaseIterable, Identifiable {
    case suspend
    case throttle

    var id: Self { self }

    fileprivate var webKitValue: WKPreferences.InactiveSchedulingPolicy {
        switch self {
        case .suspend:
            .suspend
        case .throttle:
            .throttle
        }
    }
}

@MainActor
@Observable
final class BrowserWebKitFeatureFlagStore {
    nonisolated static let preferPageRenderingUpdatesNear60FPSKey =
        "PreferPageRenderingUpdatesNear60FPSEnabled"

    private static let performanceDefaults: [String: BrowserWebKitFeatureFlagOverride] = [
        // Prefer WebKit's usual page-rendering cadence. Native scrolling can
        // still use a higher refresh rate independently of page animation work.
        preferPageRenderingUpdatesNear60FPSKey: .enabled
    ]

    static private(set) var active = BrowserWebKitFeatureFlagStore(
        registry: BrowserWebKitFeatureFlagRegistry(),
        persistence: InMemoryBrowserWebKitFeatureFlagPersistence()
    )

    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String?

    private(set) var overrides: [String: BrowserWebKitFeatureFlagOverride]
    private(set) var inactiveSchedulingPolicy: BrowserInactiveSchedulingPolicy
    private(set) var requiresRestart = false

    @ObservationIgnored
    private let crestDefaultOverrides: [String: BrowserWebKitFeatureFlagOverride]

    @ObservationIgnored
    private let registry: any BrowserWebKitFeatureFlagRegistryProviding
    @ObservationIgnored
    private let persistence: any BrowserWebKitFeatureFlagPersisting
    @ObservationIgnored
    private let inactiveSchedulingPersistence: any BrowserInactiveSchedulingPolicyPersisting

    init(
        registry: any BrowserWebKitFeatureFlagRegistryProviding,
        persistence: any BrowserWebKitFeatureFlagPersisting,
        inactiveSchedulingPersistence:
            any BrowserInactiveSchedulingPolicyPersisting =
            InMemoryBrowserInactiveSchedulingPolicyPersistence()
    ) {
        self.registry = registry
        self.persistence = persistence
        self.inactiveSchedulingPersistence = inactiveSchedulingPersistence
        features = registry.features
        availabilityFailure = registry.availabilityFailure
        let availableKeys = Set(features.map(\.key))
        crestDefaultOverrides = Self.performanceDefaults.filter {
            availableKeys.contains($0.key)
        }
        overrides = crestDefaultOverrides.merging(persistence.load()) {
            _, persistedOverride in persistedOverride
        }
        inactiveSchedulingPolicy = inactiveSchedulingPersistence.load()
    }

    static func configureForLaunch(usesIsolatedLaunch: Bool) {
        active = BrowserWebKitFeatureFlagStore(
            registry: BrowserWebKitFeatureFlagRegistry(),
            persistence: usesIsolatedLaunch
                ? InMemoryBrowserWebKitFeatureFlagPersistence()
                : UserDefaultsBrowserWebKitFeatureFlagPersistence(),
            inactiveSchedulingPersistence: usesIsolatedLaunch
                ? InMemoryBrowserInactiveSchedulingPolicyPersistence()
                : UserDefaultsBrowserInactiveSchedulingPolicyPersistence()
        )
    }

    var hasOverrides: Bool {
        overrides != crestDefaultOverrides
    }

    var activeOverrideCount: Int {
        let availableKeys = Set(features.map(\.key))
        return overrides.lazy.filter { key, override in
            availableKeys.contains(key)
                && self.crestDefaultOverrides[key] != override
        }.count
    }

    var canConfigureAllow120FPS: Bool {
        crestDefaultOverrides[
            Self.preferPageRenderingUpdatesNear60FPSKey
        ] != nil
    }

    var allows120FPS: Bool {
        get {
            overrides[
                Self.preferPageRenderingUpdatesNear60FPSKey
            ] == .disabled
        }
        set {
            setPerformanceOverride(
                newValue ? .disabled : .enabled,
                forKey: Self.preferPageRenderingUpdatesNear60FPSKey
            )
        }
    }

    var availableStatuses: [BrowserWebKitFeatureStatus] {
        Array(Set(features.map(\.status))).sorted { $0.rawValue < $1.rawValue }
    }

    var availableCategories: [BrowserWebKitFeatureCategory] {
        Array(Set(features.map(\.category))).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func override(
        for flag: BrowserWebKitFeatureFlag
    ) -> BrowserWebKitFeatureFlagOverride? {
        overrides[flag.key]
    }

    func setOverride(
        _ override: BrowserWebKitFeatureFlagOverride?,
        for flag: BrowserWebKitFeatureFlag
    ) {
        let resolvedOverride = override ?? crestDefaultOverrides[flag.key]
        guard overrides[flag.key] != resolvedOverride else { return }
        overrides[flag.key] = resolvedOverride
        persistChange()
    }

    func resetAll() {
        guard overrides != crestDefaultOverrides else { return }
        overrides = crestDefaultOverrides
        persistChange()
    }

    func apply(to preferences: WKPreferences) {
        preferences.inactiveSchedulingPolicy = inactiveSchedulingPolicy.webKitValue
        registry.apply(overrides, to: preferences)
    }

    func setInactiveSchedulingPolicy(
        _ policy: BrowserInactiveSchedulingPolicy
    ) {
        guard inactiveSchedulingPolicy != policy else { return }
        inactiveSchedulingPolicy = policy
        inactiveSchedulingPersistence.save(policy)
        requiresRestart = true
    }

    private func persistChange() {
        persistence.save(overrides)
        requiresRestart = true
    }

    private func setPerformanceOverride(
        _ override: BrowserWebKitFeatureFlagOverride,
        forKey key: String
    ) {
        guard
            crestDefaultOverrides[key] != nil,
            overrides[key] != override
        else {
            return
        }
        overrides[key] = override
        persistChange()
    }
}
