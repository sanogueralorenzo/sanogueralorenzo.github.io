import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebKitFeatureFlagTests: XCTestCase {

    func testSystemRegistryCanOverrideAndRestoreATemporaryPreferencesObject() throws {
        let registry = BrowserWebKitFeatureFlagRegistry()
        let flag = try XCTUnwrap(registry.features.first)
        let preferences = WKPreferences()
        let originalValue = try XCTUnwrap(
            registry.value(forKey: flag.key, in: preferences)
        )

        registry.apply(
            [flag.key: originalValue ? .disabled : .enabled],
            to: preferences
        )

        XCTAssertEqual(
            registry.value(forKey: flag.key, in: preferences),
            !originalValue
        )

        registry.apply(
            [flag.key: originalValue ? .enabled : .disabled],
            to: preferences
        )
        XCTAssertEqual(
            registry.value(forKey: flag.key, in: preferences),
            originalValue
        )
    }

    func testUserDefaultsPersistenceRoundTripsOverridesAndIgnoresUnknownValues() throws {
        let suiteName = "crest.tests.webkit-feature-flags.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserWebKitFeatureFlagPersistence(
            defaults: defaults
        )

        persistence.save(["EnabledFeature": .enabled, "DisabledFeature": .disabled])
        XCTAssertEqual(
            persistence.load(),
            ["EnabledFeature": .enabled, "DisabledFeature": .disabled]
        )

        defaults.set(
            ["EnabledFeature": "enabled", "OldFeature": "unexpected"],
            forKey: UserDefaultsBrowserWebKitFeatureFlagPersistence.currentKey
        )
        XCTAssertEqual(persistence.load(), ["EnabledFeature": .enabled])

        persistence.save([:])
        XCTAssertNil(
            defaults.object(
                forKey: UserDefaultsBrowserWebKitFeatureFlagPersistence.currentKey
            )
        )
    }

    func testStorePersistsTriStateChangesAndMarksTheProcessForRestart() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [BrowserWebKitFeatureFlag.preview]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        XCTAssertNil(store.override(for: BrowserWebKitFeatureFlag.preview))
        XCTAssertFalse(store.requiresRestart)

        store.setOverride(.enabled, for: BrowserWebKitFeatureFlag.preview)
        XCTAssertEqual(
            store.override(for: BrowserWebKitFeatureFlag.preview),
            .enabled
        )
        XCTAssertEqual(
            persistence.overrides,
            [BrowserWebKitFeatureFlag.preview.key: .enabled]
        )
        XCTAssertTrue(store.requiresRestart)

        store.apply(to: WKPreferences())
        XCTAssertEqual(
            registry.appliedOverrides,
            [BrowserWebKitFeatureFlag.preview.key: .enabled]
        )
        XCTAssertEqual(registry.applyCallCount, 1)

        store.setOverride(nil, for: BrowserWebKitFeatureFlag.preview)
        XCTAssertNil(store.override(for: BrowserWebKitFeatureFlag.preview))
        XCTAssertTrue(persistence.overrides.isEmpty)
    }

    func testRenderingPreferenceRevisionDiscardsTheOldChoiceAndPreservesNewOptIn() throws {
        let suiteName = "crest.tests.webkit-feature-flags.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let renderingKey = BrowserWebKitFeatureFlagStore.preferPageRenderingUpdatesNear60FPSKey
        defaults.set(
            [renderingKey: "disabled", BrowserWebKitFeatureFlag.preview.key: "enabled"],
            forKey: UserDefaultsBrowserWebKitFeatureFlagPersistence.currentKey
        )
        let persistence = UserDefaultsBrowserWebKitFeatureFlagPersistence(defaults: defaults)
        let registry = StubBrowserWebKitFeatureFlagRegistry(features: [.preferNear60FPS, .preview])
        let store = BrowserWebKitFeatureFlagStore(registry: registry, persistence: persistence)

        XCTAssertFalse(store.allows120FPS)
        XCTAssertEqual(store.override(for: .preview), .enabled)

        store.allows120FPS = true
        let relaunchedStore = BrowserWebKitFeatureFlagStore(registry: registry, persistence: persistence)

        XCTAssertTrue(relaunchedStore.allows120FPS)
        XCTAssertEqual(relaunchedStore.override(for: .preview), .enabled)
    }

    func testAllow120FPSSettingPersistsAndStaysInSyncWithRawOverride() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        store.allows120FPS = true

        XCTAssertTrue(store.allows120FPS)
        XCTAssertEqual(store.activeOverrideCount, 1)
        XCTAssertEqual(
            persistence.overrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .disabled
            ]
        )

        let relaunchedStore = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )
        XCTAssertTrue(relaunchedStore.allows120FPS)

        store.setOverride(.enabled, for: .preferNear60FPS)

        XCTAssertFalse(store.allows120FPS)
        XCTAssertFalse(store.hasOverrides)

        store.setOverride(nil, for: .preferNear60FPS)

        XCTAssertFalse(store.allows120FPS)
    }

    func testInactiveSchedulingPolicyPersistsAndAppliesToNewPreferences() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(features: [])
        let flagPersistence = InMemoryBrowserWebKitFeatureFlagPersistence()
        let schedulingPersistence =
            InMemoryBrowserInactiveSchedulingPolicyPersistence()
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: flagPersistence,
            inactiveSchedulingPersistence: schedulingPersistence
        )
        let preferences = WKPreferences()

        XCTAssertEqual(store.inactiveSchedulingPolicy, .suspend)
        XCTAssertFalse(store.requiresRestart)

        store.setInactiveSchedulingPolicy(.throttle)
        store.apply(to: preferences)

        XCTAssertEqual(store.inactiveSchedulingPolicy, .throttle)
        XCTAssertEqual(schedulingPersistence.policy, .throttle)
        XCTAssertEqual(preferences.inactiveSchedulingPolicy, .throttle)
        XCTAssertTrue(store.requiresRestart)

        let relaunchedStore = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: flagPersistence,
            inactiveSchedulingPersistence: schedulingPersistence
        )
        XCTAssertEqual(relaunchedStore.inactiveSchedulingPolicy, .throttle)
    }

    func testInactiveSchedulingPolicyUserDefaultsPersistenceUsesSuspendFallback() throws {
        let suiteName = "crest.tests.webkit-inactive-scheduling.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence =
            UserDefaultsBrowserInactiveSchedulingPolicyPersistence(
                defaults: defaults
            )

        XCTAssertEqual(persistence.load(), .suspend)

        persistence.save(.throttle)
        XCTAssertEqual(persistence.load(), .throttle)

        defaults.set(
            "unexpected",
            forKey:
                UserDefaultsBrowserInactiveSchedulingPolicyPersistence
                .currentKey
        )
        XCTAssertEqual(persistence.load(), .suspend)
    }

    func testResetAllRestoresCrestPerformanceDefaults() {
        let registry = StubBrowserWebKitFeatureFlagRegistry(
            features: [.preferNear60FPS, .scrollAnimator, .preview]
        )
        let persistence = InMemoryBrowserWebKitFeatureFlagPersistence(
            overrides: [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .disabled,
                BrowserWebKitFeatureFlag.scrollAnimator.key: .disabled,
                BrowserWebKitFeatureFlag.preview.key: .enabled,
            ]
        )
        let store = BrowserWebKitFeatureFlagStore(
            registry: registry,
            persistence: persistence
        )

        store.resetAll()

        XCTAssertFalse(store.allows120FPS)
        XCTAssertNil(store.override(for: .scrollAnimator))
        XCTAssertFalse(store.hasOverrides)
        XCTAssertEqual(
            persistence.overrides,
            [
                BrowserWebKitFeatureFlagStore
                    .preferPageRenderingUpdatesNear60FPSKey: .enabled
            ]
        )
    }

}

@MainActor
private final class StubBrowserWebKitFeatureFlagRegistry:
    BrowserWebKitFeatureFlagRegistryProviding
{
    let features: [BrowserWebKitFeatureFlag]
    let availabilityFailure: String? = nil
    private(set) var appliedOverrides: [String: BrowserWebKitFeatureFlagOverride] = [:]
    private(set) var applyCallCount = 0

    init(features: [BrowserWebKitFeatureFlag]) {
        self.features = features
    }

    func apply(
        _ overrides: [String: BrowserWebKitFeatureFlagOverride],
        to preferences: WKPreferences
    ) {
        appliedOverrides = overrides
        applyCallCount += 1
    }
}

extension BrowserWebKitFeatureFlag {
    fileprivate static let preview = BrowserWebKitFeatureFlag(
        key: "PreviewAnimationEnabled",
        name: "Preview Animation",
        details: "Enable a preview animation feature",
        status: BrowserWebKitFeatureStatus(rawValue: 5),
        category: BrowserWebKitFeatureCategory(rawValue: 2),
        defaultValue: false
    )

    fileprivate static let stable = BrowserWebKitFeatureFlag(
        key: "StableDOMEnabled",
        name: "Stable DOM",
        details: "Enable a stable DOM feature",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: true
    )

    fileprivate static let media = BrowserWebKitFeatureFlag(
        key: "MediaTestingEnabled",
        name: "Media Testing",
        details: "Enable media testing",
        status: BrowserWebKitFeatureStatus(rawValue: 4),
        category: BrowserWebKitFeatureCategory(rawValue: 7),
        defaultValue: false
    )

    fileprivate static let preferNear60FPS = BrowserWebKitFeatureFlag(
        key: BrowserWebKitFeatureFlagStore
            .preferPageRenderingUpdatesNear60FPSKey,
        name: "Prefer Page Rendering Updates Near 60 FPS",
        details: "Prefer page rendering updates near 60 FPS",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: true
    )

    fileprivate static let scrollAnimator = BrowserWebKitFeatureFlag(
        key: "ScrollAnimatorEnabled",
        name: "Scroll Animator",
        details: "Use the WebKit scroll animator",
        status: BrowserWebKitFeatureStatus(rawValue: 6),
        category: BrowserWebKitFeatureCategory(rawValue: 3),
        defaultValue: false
    )
}
