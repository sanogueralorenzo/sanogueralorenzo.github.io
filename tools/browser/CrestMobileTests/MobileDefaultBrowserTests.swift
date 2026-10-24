import XCTest

@testable import CrestMobile

@MainActor
final class MobileDefaultBrowserTests: XCTestCase {
    func testMobileApplicationBundlesTheMinimalCrestPrivacyManifest() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            Set(manifest.keys),
            [
                "NSPrivacyTracking",
                "NSPrivacyCollectedDataTypes",
                "NSPrivacyAccessedAPITypes",
            ])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        let collectedDataTypes = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        XCTAssertTrue(collectedDataTypes.isEmpty)

        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let reasons = try Dictionary(
            uniqueKeysWithValues: entries.map { entry in
                (
                    try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                    try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
                )
            })
        XCTAssertEqual(
            reasons,
            [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
            ])
    }

    func testPasskeyBuildManifestIsEnabledAfterTheManagedEntitlementIsProvisioned() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestBrowserPasskeyManagedCapability"
            ) as? Bool,
            true
        )
    }

    func testSystemPasswordWriteThroughManifestIsEnabledAfterBrowserApproval() throws {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestSystemPasswordWriteThroughManagedCapability"
            ) as? Bool,
            true
        )
        let facts = BrowserSystemPasswordWriteThroughSystem.facts(
            for: BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false))
        XCTAssertEqual(try CrestCore().query(facts).availability, .available)
    }

    func testMobileApplicationRegistersBothWebURLSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]]
        )
        let schemes = Set(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )

        XCTAssertTrue(schemes.contains("http"))
        XCTAssertTrue(schemes.contains("https"))
    }

    func testMobileApplicationSupportsIndependentNativeWindowScenes() throws {
        let sceneManifest = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                as? [String: Any]
        )

        XCTAssertEqual(
            sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool,
            true
        )
    }

    func testApprovedDefaultBrowserFlowOpensSystemSettingsWithoutImplicitStatusCheck() {
        var statusCheckCount = 0
        var settingsOpenCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .systemSettings,
            statusCheck: {
                statusCheckCount += 1
                return false
            },
            defaultRequest: {},
            settingsOpener: { settingsOpenCount += 1 }
        )

        XCTAssertEqual(controller.requestStyle, .systemSettings)
        controller.openSystemSettings()

        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertEqual(statusCheckCount, 0)
        XCTAssertEqual(controller.status, .unknown)
    }

}
