import XCTest

@testable import Crest

final class BrowserSafeStorageIsolationTests: XCTestCase {
    func testIsolatedAndForcedOnboardingUseUnavailableSafeStorage() {
        for values in [
            ["CREST_ISOLATED_SESSION": "1"],
            ["CREST_SHOW_SETUP": "1"],
        ] {
            let safeStorage = LaunchScopedBrowserSafeStorage(
                launchEnvironment: BrowserLaunchEnvironment(
                    values: values,
                    isXCTestRuntime: false
                ),
                systemStorage: {
                    XCTFail(
                        "Isolated onboarding must not construct the system safe-storage provider."
                    )
                    return TestSafeStorage(secret: "unexpected-secret")
                }
            )

            XCTAssertThrowsError(try safeStorage.secret(for: .chrome)) { error in
                XCTAssertEqual(
                    error as? BrowserPasswordImportError,
                    .safeStorageUnavailable
                )
            }
        }
    }

    func testOrdinaryLaunchForwardsToTheSystemSafeStorageProvider() throws {
        let safeStorage = LaunchScopedBrowserSafeStorage(
            launchEnvironment: BrowserLaunchEnvironment(
                values: [:],
                isXCTestRuntime: false
            ),
            systemStorage: {
                TestSafeStorage(secret: "ordinary-secret")
            }
        )

        XCTAssertEqual(
            try safeStorage.secret(for: .chrome),
            "ordinary-secret"
        )
    }

    private struct TestSafeStorage: BrowserSafeStorageSecretProviding {
        let secret: String

        func secret(for application: ImportSource) throws -> String {
            secret
        }
    }
}
