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

    /// Each fixture input reaches the core's isolation rule through the
    /// environment's own parsing. The rule itself is the core's.
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

    /// The extension pool a named isolated launch composes keeps its
    /// installations, so a validation relaunch does not begin by re-adding
    /// every extension while WebKit still holds their storage.

    /// A profile name is a directory name too, so anything that could climb
    /// out of the isolated root is refused rather than staged.
}
