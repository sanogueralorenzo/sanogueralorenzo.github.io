import XCTest

@testable import Crest

final class BrowserLaunchEnvironmentTests: XCTestCase {
    func testCloudReviewRequiresExplicitNamedIsolationAndNeverUsesTheProductionZone() throws {
        let configuration = BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
        let values = [
            "CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": "device-one",
            "CREST_ISOLATED_CLOUD_SYNC_ID": "shared-review",
        ]
        let review = try XCTUnwrap(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: false)))
        XCTAssertEqual(review.zoneName, "CrestReview-shared-review")
        XCTAssertNotEqual(review.zoneName, configuration.zoneName)
        for omitted in values.keys {
            var incomplete = values
            incomplete[omitted] = nil
            XCTAssertNil(
                configuration.isolated(
                    for:
                        BrowserLaunchEnvironment(values: incomplete, isXCTestRuntime: false)))
        }
        XCTAssertNil(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: true)))
        XCTAssertNil(
            configuration.isolated(
                for:
                    BrowserLaunchEnvironment(values: values, isXCTestRuntime: false, isSwiftUIPreviewRuntime: true)))
        for invalid in ["../CrestPrivate", "Shared Review", "", String(repeating: "a", count: 49)] {
            var malformed = values
            malformed["CREST_ISOLATED_CLOUD_SYNC_ID"] = invalid
            XCTAssertNil(
                configuration.isolated(
                    for:
                        BrowserLaunchEnvironment(values: malformed, isXCTestRuntime: false)))
            XCTAssertTrue(
                BrowserLaunchEnvironment(
                    values: ["CREST_ISOLATED_CLOUD_SYNC_ID": invalid],
                    isXCTestRuntime: false
                ).requiresIsolation)
        }
    }

    func testIsolatedLaunchesNeverAdoptTheInstalledDeviceChoices() throws {
        let installedName = "BrowserLaunchEnvironmentTests.installed.\(UUID().uuidString)"
        let installed = try XCTUnwrap(UserDefaults(suiteName: installedName))
        let isolationID = "device-choices-\(UUID().uuidString.prefix(8).lowercased())"
        let isolatedName = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        let isolated = try XCTUnwrap(UserDefaults(suiteName: isolatedName))
        defer {
            installed.removePersistentDomain(forName: installedName)
            isolated.removePersistentDomain(forName: isolatedName)
        }
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.sitePermissionsKey)
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.shortcutsKey)
        installed.set(Data("installed".utf8), forKey: BrowserLegacyDeviceDefaults.linkPreferencesKey)
        installed.set(true, forKey: BrowserLegacyDeviceDefaults.setupCompletedKey)
        isolated.set(Data("isolated".utf8), forKey: BrowserLegacyDeviceDefaults.shortcutsKey)

        let product = BrowserLegacyDeviceDefaults.read(
            for: BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false), standard: installed)
        XCTAssertEqual(product.sitePermissions, Data("installed".utf8))
        XCTAssertEqual(product.shortcuts, Data("installed".utf8))
        XCTAssertEqual(product.linkPreferences, Data("installed".utf8))
        XCTAssertTrue(product.setupCompleted)
        let namedLaunch = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
        let named = BrowserLegacyDeviceDefaults.read(for: namedLaunch, standard: installed)
        XCTAssertNil(named.sitePermissions)
        XCTAssertNil(named.linkPreferences)
        XCTAssertEqual(named.shortcuts, Data("isolated".utf8))
        XCTAssertFalse(named.setupCompleted)
        let memoryOnlyLaunch = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let memoryOnly = BrowserLegacyDeviceDefaults.read(for: memoryOnlyLaunch, standard: installed)
        XCTAssertEqual(memoryOnly, BrowserLegacyDeviceDefaults())
    }

    func testParsesEveryOwnedLaunchValueWithoutLosingRawFixtureInputs() {
        let environment = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "1",
                "CREST_ISOLATED_PERSISTENCE_ID": "APP-252 Verification!",
                "CREST_RESET_SESSION": "1",
                "CREST_SHOWCASE_SESSION": "1",
                "CREST_USE_IN_MEMORY_CREDENTIALS": "1",
                "CREST_SHOW_ONBOARDING": "1",
                "CREST_SHOW_SETUP": "1",
                "CREST_FORCE_ONBOARDING_SETUP": "1",
                "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/",
                "CREST_PERFORMANCE_TAB_COUNT": "12",
                "CREST_PERFORMANCE_HEAVY_SESSION": "1",
                "CREST_PERFORMANCE_RUN_ID": "run-42",
                "CREST_UPDATE_WIDGET_FIXTURE": "ready:0.5.99:599",
                "CREST_UPDATE_TEST_FEED_URL": "http://127.0.0.1:48151/appcast.xml",
            ],
            isXCTestRuntime: true,
            isSwiftUIPreviewRuntime: true
        )

        XCTAssertTrue(environment.explicitlyRequiresIsolation)
        XCTAssertEqual(environment.persistentIsolationID, "app-252verification")
        XCTAssertTrue(environment.resetsSession)
        XCTAssertTrue(environment.presentsShowcaseSession)
        XCTAssertTrue(environment.usesInMemoryCredentialVault)
        XCTAssertTrue(environment.forcesOnboardingWelcome)
        XCTAssertTrue(environment.forcesMacOnboardingSetup)
        XCTAssertTrue(environment.forcesMobileOnboardingSetup)
        XCTAssertEqual(
            environment.performanceBaseURLString,
            "http://127.0.0.1:8080/"
        )
        XCTAssertEqual(environment.performanceTabCount, "12")
        XCTAssertTrue(environment.performanceHeavySession)
        XCTAssertEqual(environment.performanceRunID, "run-42")
        XCTAssertEqual(
            environment.softwareUpdateWidgetFixture,
            "ready:0.5.99:599"
        )
        XCTAssertEqual(
            environment.isolatedSoftwareUpdateFeedURL?.absoluteString,
            "http://127.0.0.1:48151/appcast.xml"
        )
        XCTAssertTrue(environment.isXCTestRuntime)
        XCTAssertTrue(environment.isSwiftUIPreviewRuntime)
    }

    func testOnlyTheExactEnabledMarkerTurnsOnLaunchFlags() {
        let environment = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "true",
                "CREST_RESET_SESSION": "true",
                "CREST_SHOWCASE_SESSION": "01",
                "CREST_USE_IN_MEMORY_CREDENTIALS": "0",
                "CREST_SHOW_ONBOARDING": "YES",
                "CREST_SHOW_SETUP": "",
                "CREST_FORCE_ONBOARDING_SETUP": "false",
            ],
            isXCTestRuntime: false
        )

        XCTAssertFalse(environment.resetsSession)
        XCTAssertFalse(environment.explicitlyRequiresIsolation)
        XCTAssertFalse(environment.presentsShowcaseSession)
        XCTAssertFalse(environment.usesInMemoryCredentialVault)
        XCTAssertFalse(environment.forcesOnboardingWelcome)
        XCTAssertFalse(environment.forcesMacOnboardingSetup)
        XCTAssertFalse(environment.forcesMobileOnboardingSetup)
        XCTAssertNil(environment.persistentIsolationID)
    }

    func testMissingPerformanceRunIDKeepsTheReleaseSoakFallback() {
        let environment = BrowserLaunchEnvironment(
            values: [:],
            isXCTestRuntime: false
        )

        XCTAssertNil(environment.performanceBaseURLString)
        XCTAssertNil(environment.performanceTabCount)
        XCTAssertFalse(environment.performanceHeavySession)
        XCTAssertEqual(environment.performanceRunID, "release-soak")
    }

    func testUpdateTestFeedAcceptsOnlyLoopbackHTTPURLs() {
        let rejectedValues = [
            "https://raw.githubusercontent.com/example/appcast.xml",
            "http://example.com/appcast.xml",
            "file:///tmp/appcast.xml",
        ]

        for value in rejectedValues {
            let environment = BrowserLaunchEnvironment(
                values: ["CREST_UPDATE_TEST_FEED_URL": value],
                isXCTestRuntime: false
            )
            XCTAssertNil(environment.isolatedSoftwareUpdateFeedURL)
        }
    }

    /// Each fixture input reaches the core's isolation rule through the
    /// environment's own parsing, including the performance harness whose
    /// base address counts even when empty. The rule itself is the core's.
    func testEveryFixtureLaunchFlagUsesAnIsolatedDataGraph() {
        let fixtures: [[String: String]] = [
            ["CREST_ISOLATED_SESSION": "1"],
            ["CREST_RESET_SESSION": "1"],
            ["CREST_SHOWCASE_SESSION": "1"],
            ["CREST_USE_IN_MEMORY_CREDENTIALS": "1"],
            ["CREST_SHOW_ONBOARDING": "1"],
            ["CREST_SHOW_SETUP": "1"],
            ["CREST_FORCE_ONBOARDING_SETUP": "1"],
            ["CREST_ISOLATED_CLOUD_SYNC_ID": "review"],
            ["CREST_PERFORMANCE_BASE_URL": ""],
            ["CREST_UPDATE_TEST_FEED_URL": "http://localhost:48151/appcast.xml"],
        ]

        for values in fixtures {
            XCTAssertTrue(
                BrowserLaunchEnvironment(values: values, isXCTestRuntime: false).requiresIsolation,
                "\(values) must never use the installed app's persistence graph."
            )
        }
        let tests = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
        XCTAssertTrue(tests.requiresIsolation)
        XCTAssertFalse(tests.presentsInstalledApplicationUI)
        let installed = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
        XCTAssertFalse(installed.requiresIsolation)
        XCTAssertTrue(installed.presentsInstalledApplicationUI)
    }

    /// A named isolated profile persists its WebKit storage, so it has to
    /// persist the record of what is installed as well. An anonymous isolated
    /// launch keeps forgetting both.
    func testOnlyANamedIsolatedProfileKeepsPersistentProfileStorage() {
        let named = BrowserLaunchEnvironment(
            values: [
                "CREST_ISOLATED_SESSION": "1",
                "CREST_ISOLATED_PERSISTENCE_ID": "app-252-verification",
            ],
            isXCTestRuntime: false
        )
        let anonymous = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"],
            isXCTestRuntime: false
        )

        XCTAssertTrue(named.requiresIsolation)
        XCTAssertFalse(named.usesEphemeralProfileStorage)
        XCTAssertTrue(anonymous.usesEphemeralProfileStorage)
        XCTAssertEqual(
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            "\(ProductIdentity.serviceNamespace).isolated.app-252-verification"
        )
        XCTAssertNotEqual(
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-252-verification"
            ),
            BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
                isolationID: "app-283-verification"
            )
        )
    }

    /// The extension pool a named isolated launch composes keeps its
    /// installations, so a validation relaunch does not begin by re-adding
    /// every extension while WebKit still holds their storage.

    /// A profile name is a directory name too, so anything that could climb
    /// out of the isolated root is refused rather than staged.

    @MainActor
    func testProductionCompositionRedirectsFixtureInputsToInMemoryOwners() throws {
        let environments = [
            BrowserLaunchEnvironment(
                values: ["CREST_RESET_SESSION": "1"],
                isXCTestRuntime: false
            ),
            BrowserLaunchEnvironment(
                values: [
                    "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/"
                ],
                isXCTestRuntime: false
            ),
        ]

        for environment in environments {
            let core = try BrowserStore.launchCore(for: environment)
            XCTAssertNil(core.storageDirectory, "A fixture launch keeps its session in memory")
            let store = try BrowserStore.production(core: core, launchEnvironment: environment)

            XCTAssertTrue(store.credentialVault is InMemoryCredentialVault)
            // Only the session the core keeps in its file syncs.
            XCTAssertFalse(store.syncsSession)
        }
    }
}
