import XCTest

@testable import Crest

final class BrowserPrivacyManifestTests: XCTestCase {
    func testMacApplicationBundlesTheMinimalCrestPrivacyManifest() throws {
        let manifest = try privacyManifest(in: .main)

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
        XCTAssertEqual(
            try accessedAPIReasons(in: manifest),
            [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
            ])
    }

    private func privacyManifest(in bundle: Bundle) throws -> [String: Any] {
        let url = try XCTUnwrap(
            bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }

    private func accessedAPIReasons(
        in manifest: [String: Any]
    ) throws -> [String: [String]] {
        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        return try Dictionary(
            uniqueKeysWithValues: entries.map { entry in
                (
                    try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                    try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
                )
            })
    }
}
