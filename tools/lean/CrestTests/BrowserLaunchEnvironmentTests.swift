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

        let product = BrowserLegacyDeviceDefaults.read(
            for: BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false), standard: installed)
        XCTAssertEqual(product.sitePermissions, Data("installed".utf8))
        let namedLaunch = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
        let named = BrowserLegacyDeviceDefaults.read(for: namedLaunch, standard: installed)
        XCTAssertNil(named.sitePermissions)
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
                "CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/",
                "CREST_PERFORMANCE_TAB_COUNT": "12",
                "CREST_PERFORMANCE_HEAVY_SESSION": "1",
                "CREST_PERFORMANCE_RUN_ID": "run-42",
                "CREST_UPDATE_TEST_FEED_URL": "http://127.0.0.1:48151/appcast.xml",
            ],
            isXCTestRuntime: true,
            isSwiftUIPreviewRuntime: true
        )

        XCTAssertTrue(environment.explicitlyRequiresIsolation)
        XCTAssertEqual(environment.persistentIsolationID, "app-252verification")
        XCTAssertTrue(environment.resetsSession)
        XCTAssertTrue(environment.presentsShowcaseSession)
        XCTAssertEqual(
            environment.performanceBaseURLString,
            "http://127.0.0.1:8080/"
        )
        XCTAssertEqual(environment.performanceTabCount, "12")
        XCTAssertTrue(environment.performanceHeavySession)
        XCTAssertEqual(environment.performanceRunID, "run-42")
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
            ],
            isXCTestRuntime: false
        )

        XCTAssertFalse(environment.resetsSession)
        XCTAssertFalse(environment.explicitlyRequiresIsolation)
        XCTAssertFalse(environment.presentsShowcaseSession)
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

    /// Every fixture input isolates the actual launch data graph.
    func testEveryFixtureLaunchFlagUsesAnIsolatedDataGraph() {
        let fixtures: [[String: String]] = [
            ["CREST_ISOLATED_SESSION": "1"],
            ["CREST_RESET_SESSION": "1"],
            ["CREST_SHOWCASE_SESSION": "1"],
            ["CREST_ISOLATED_CLOUD_SYNC_ID": "review"],
            ["CREST_PERFORMANCE_BASE_URL": "http://127.0.0.1:8080/"],
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
        XCTAssertTrue(tests.usesEphemeralProfileStorage)
        XCTAssertFalse(tests.presentsInstalledApplicationUI)
        let preview = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false, isSwiftUIPreviewRuntime: true)
        XCTAssertTrue(preview.requiresIsolation)
        XCTAssertTrue(preview.usesEphemeralProfileStorage)
        XCTAssertTrue(preview.presentsInstalledApplicationUI)
        let installed = BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
        XCTAssertFalse(installed.requiresIsolation)
        XCTAssertFalse(installed.usesEphemeralProfileStorage)
        XCTAssertTrue(installed.presentsInstalledApplicationUI)
    }

    /// A named isolated profile persists its WebKit storage, so it has to
    /// persist the record of what is installed as well. An anonymous isolated
    /// launch keeps forgetting both.
    func testOnlyANamedIsolatedProfileKeepsPersistentProfileStorage() {
        let nameAlone = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_PERSISTENCE_ID": "app-252-verification"], isXCTestRuntime: false)
        XCTAssertFalse(nameAlone.requiresIsolation)
        XCTAssertFalse(nameAlone.usesEphemeralProfileStorage)
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

    /// A local launch starts blank and restores profile edits rather than
    /// replacing them with preview content on relaunch.
    @MainActor
    func testLocalLaunchStartsBlankAndRestoresSavedEditsWithoutReseeding() throws {
        let isolationID = "blank-\(UUID().uuidString.lowercased())"
        let namespace = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: namespace))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: namespace)
            try? FileManager.default.removeItem(at: directory)
        }
        let environment = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": isolationID],
            isXCTestRuntime: false)
        let saved: SessionState.Seed
        do {
            let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
            let store = try BrowserStore.production(core: core, launchEnvironment: environment)
            let space = try XCTUnwrap(store.spaceModels.first)
            XCTAssertEqual(store.spaceModels.count, 1)
            XCTAssertTrue(space.folders.models.isEmpty)
            XCTAssertEqual(space.tabs.models.count, 1)
            XCTAssertNil(space.tabs.models.first?.url)

            let url = try XCTUnwrap(URL(string: "https://startup.example/"))
            let tabID = try XCTUnwrap(store.openNewTab(url: url))
            store.pinTab(tabID)
            store.deleteTab(tabID, in: space.id)
            XCTAssertFalse(space.tabs.contains(tabID))
            store.updateSpaceIdentity(space.id, name: "Saved")
            saved = store.sessionSeed
        }
        let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let restored = try BrowserStore.production(core: core, launchEnvironment: environment)
        XCTAssertEqual(restored.sessionSeed, saved)
        XCTAssertTrue(try XCTUnwrap(restored.spaceModels.first).pinnedTabs.isEmpty)

        let anonymous = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"], isXCTestRuntime: false)
        let transient = try BrowserStore.production(core: CrestCore(), launchEnvironment: anonymous)
        XCTAssertEqual(transient.spaceModels.count, 1)
        XCTAssertEqual(transient.spaceModels.first?.tabs.models.count, 1)
        XCTAssertNil(transient.spaceModels.first?.tabs.models.first?.url)
    }

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

            // Only the session the core keeps in its file syncs.
            XCTAssertFalse(store.syncsSession)
        }
    }
}
