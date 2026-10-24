import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateRefreshTests: XCTestCase {
    func testDownloadRefreshesAnOldOfferAndInstallsOnlyTheNewestBuild() {
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        let feed = TestSignedUpdateFeed(item: .init(version: "0.5.20", build: "1064"))
        feed.presentNewest(in: model, userInitiated: false)
        updater.sessionInProgress = true
        updater.onUserInitiatedCheck = {
            feed.presentNewest(in: model, userInitiated: true)
            coordinator.updateWasFound()
        }
        feed.item = .init(version: "0.5.22", build: "1066")

        model.installUpdate()

        XCTAssertEqual(model.phase, .checking)
        XCTAssertEqual(feed.dismissedBuilds, ["1064"])
        XCTAssertEqual(feed.installedBuilds, [])
        updater.sessionInProgress = false
        coordinator.updateCycleDidFinish()

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
        XCTAssertEqual(model.updateBuild, "1066")
        XCTAssertEqual(model.phase, .downloading)
        XCTAssertEqual(feed.installedBuilds, ["1066"])
        XCTAssertEqual(feed.skippedBuilds, [])
    }

    func testActivationDoesNotReplaceAPendingDownloadWithABackgroundCheck() {
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        updater.automaticallyChecksForUpdates = true
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(updater: updater, model: model)
        let feed = TestSignedUpdateFeed(item: .init(version: "0.5.22", build: "1066"))
        feed.presentNewest(in: model, userInitiated: false)
        updater.sessionInProgress = true
        updater.onUserInitiatedCheck = {
            feed.presentNewest(in: model, userInitiated: true)
            coordinator.updateWasFound()
        }

        model.installUpdate()
        coordinator.applicationDidBecomeActive(at: .distantFuture)
        updater.sessionInProgress = false
        coordinator.updateCycleDidFinish()

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
        XCTAssertEqual(updater.backgroundCheckCount, 0)
        XCTAssertEqual(feed.installedBuilds, ["1066"])
    }

    func testManualCheckDismissesStaleOfferBeforeLoadingNewestGeneration() {
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        let feed = TestSignedUpdateFeed(
            item: .init(version: "0.5.0", build: "1051")
        )
        feed.presentNewest(
            in: model,
            userInitiated: false
        )
        updater.sessionInProgress = true
        updater.onUserInitiatedCheck = {
            feed.presentNewest(
                in: model,
                userInitiated: true
            )
            coordinator.updateWasFound()
        }

        feed.item = .init(version: "0.5.6", build: "1052")
        coordinator.checkForUpdates()

        XCTAssertEqual(feed.dismissedBuilds, ["1051"])
        XCTAssertEqual(feed.skippedBuilds, [])
        XCTAssertEqual(feed.installedBuilds, [])
        XCTAssertEqual(updater.userInitiatedCheckCount, 0)
        XCTAssertEqual(model.phase, .checking)
        XCTAssertEqual(model.sidebarWidgetSnapshot?.build, "1051")

        updater.sessionInProgress = false
        coordinator.updateCycleDidFinish()

        XCTAssertEqual(updater.userInitiatedCheckCount, 1)
        XCTAssertEqual(model.phase, .available)
        XCTAssertEqual(model.updateBuild, "1052")

        model.installUpdate()

        XCTAssertEqual(feed.installedBuilds, ["1052"])
        XCTAssertEqual(feed.skippedBuilds, [])
    }

    func testOverdueActivationRefreshesStaleOfferInBackground() {
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        updater.automaticallyChecksForUpdates = true
        updater.lastUpdateCheckDate = now.addingTimeInterval(-3_601)
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        let feed = TestSignedUpdateFeed(
            item: .init(version: "0.5.0", build: "1051")
        )
        feed.presentNewest(
            in: model,
            userInitiated: false
        )
        updater.sessionInProgress = true
        updater.onBackgroundCheck = {
            feed.presentNewest(
                in: model,
                userInitiated: false
            )
        }

        feed.item = .init(version: "0.5.6", build: "1052")
        coordinator.applicationDidBecomeActive(at: now)

        XCTAssertEqual(feed.dismissedBuilds, ["1051"])
        XCTAssertEqual(updater.backgroundCheckCount, 0)

        updater.sessionInProgress = false
        coordinator.updateCycleDidFinish()

        XCTAssertEqual(updater.backgroundCheckCount, 1)
        XCTAssertEqual(model.updateBuild, "1052")
        XCTAssertEqual(feed.skippedBuilds, [])
        XCTAssertEqual(feed.installedBuilds, [])
    }

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

    func testChannelChangeDismissesOldOfferWithoutCrossingDisabledPreference() {
        let model = BrowserSoftwareUpdateModel()
        let updater = TestSoftwareUpdateChecker()
        updater.automaticallyChecksForUpdates = false
        let coordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        var dismissCount = 0
        var skipCount = 0
        model.presentUpdate(
            title: "Crest 0.5.0",
            version: "0.5.0",
            build: "1051",
            isInformationOnly: false,
            install: {},
            skip: { skipCount += 1 },
            dismiss: { dismissCount += 1 }
        )
        updater.sessionInProgress = true

        coordinator.channelDidChange()

        XCTAssertEqual(updater.resetCycleCount, 1)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(skipCount, 0)
        updater.sessionInProgress = false
        coordinator.updateCycleDidFinish()
        XCTAssertEqual(updater.backgroundCheckCount, 0)
        XCTAssertEqual(model.phase, .idle)
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

@MainActor
private final class TestSignedUpdateFeed {
    struct Item {
        let version: String
        let build: String
    }

    var item: Item
    private(set) var dismissedBuilds: [String] = []
    private(set) var skippedBuilds: [String] = []
    private(set) var installedBuilds: [String] = []

    init(item: Item) {
        self.item = item
    }

    func presentNewest(
        in model: BrowserSoftwareUpdateModel,
        userInitiated: Bool
    ) {
        let item = item
        model.presentUpdate(
            title: "Crest \(item.version)",
            version: item.version,
            build: item.build,
            isInformationOnly: false,
            install: { [weak self] in self?.installedBuilds.append(item.build) },
            skip: { [weak self] in self?.skippedBuilds.append(item.build) },
            dismiss: { [weak self] in self?.dismissedBuilds.append(item.build) }
        )
    }
}
