import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateRefreshTests: XCTestCase {
    func testLaunchAndActivationRespectAutomaticPreferenceAndMinimumInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        updater.automaticallyChecksForUpdates = true
        updater.lastUpdateCheckDate = now.addingTimeInterval(
            -BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval
        )
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )

        coordinator.updaterDidStart(at: now)
        XCTAssertEqual(updater.backgroundCheckCount, 1)

        updater.lastUpdateCheckDate = now
        coordinator.applicationDidBecomeActive(
            at: now.addingTimeInterval(
                BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval - 1
            )
        )
        XCTAssertEqual(updater.backgroundCheckCount, 1)

        coordinator.applicationDidBecomeActive(
            at: now.addingTimeInterval(
                BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval
            )
        )
        XCTAssertEqual(updater.backgroundCheckCount, 2)

        updater.automaticallyChecksForUpdates = false
        updater.lastUpdateCheckDate = now
        coordinator.applicationDidBecomeActive(
            at: now.addingTimeInterval(
                BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval * 2
            )
        )
        XCTAssertEqual(updater.backgroundCheckCount, 2)

        coordinator.checkForUpdates()
        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
    }

}

@MainActor
private final class TestSoftwareUpdateChecker: BrowserSoftwareUpdateChecking {
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var sessionInProgress = false
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    var backgroundCheckCount = 0
    var userInitiatedCheckCount = 0
    var resetCycleCount = 0
    var backgroundAutomaticDownloadValues: [Bool] = []
    var userInitiatedAutomaticDownloadValues: [Bool] = []
    var onBackgroundCheck: (() -> Void)?
    var onUserInitiatedCheck: (() -> Void)?

    func checkForUpdates() {
        userInitiatedCheckCount += 1
        userInitiatedAutomaticDownloadValues.append(automaticallyDownloadsUpdates)
        onUserInitiatedCheck?()
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCount += 1
        backgroundAutomaticDownloadValues.append(automaticallyDownloadsUpdates)
        onBackgroundCheck?()
    }

    func resetUpdateCycleAfterShortDelay() {
        resetCycleCount += 1
    }
}
