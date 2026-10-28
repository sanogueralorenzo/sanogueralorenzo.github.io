import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateTests: XCTestCase {
    func testApplicationRequiresSignedSparkleUpdatesFromTheOfficialFeed() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast.xml"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "x/dBoNAjtYIa+JKUUHY48NYepidnElHTo3w2VMyqzLA="
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool,
            true
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval")
                as? Double,
            BrowserSoftwareUpdateRefreshCoordinator.minimumAutomaticCheckInterval
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool,
            true
        )
    }

    func testStableUpdatesKeepTheInstalledEngineComposition() {
        XCTAssertNil(BrowserSoftwareUpdateFeed(for: .chromium).url)
        XCTAssertEqual(
            BrowserSoftwareUpdateFeed(for: .webKit).url?.absoluteString,
            "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-webkit.xml")
    }

    func testDownloadProgressAccumulatesAndClampsToTheExpectedLength() throws {
        let model = BrowserSoftwareUpdateModel()

        model.presentDownload(cancellation: {})
        model.setExpectedDownloadLength(100)
        model.receiveDownloadedBytes(30)
        XCTAssertEqual(try XCTUnwrap(model.progress), 0.3, accuracy: 0.001)

        model.receiveDownloadedBytes(90)
        XCTAssertEqual(try XCTUnwrap(model.progress), 1, accuracy: 0.001)
    }

    func testARelaunchCrestDidNotQuitForIsOfferedAgain() throws {
        let model = BrowserSoftwareUpdateModel()
        var relaunchRequests = 0
        model.presentAutomaticUpdateReady(
            title: "Crest 0.5.1",
            version: "0.5.1",
            build: "501",
            releaseNotes: nil,
            informationURL: nil,
            installAndRelaunch: { relaunchRequests += 1 }
        )

        model.installAndRelaunchNow()
        XCTAssertEqual(relaunchRequests, 1)
        XCTAssertEqual(model.phase, .installing)

        model.applicationStayedOpen()
        XCTAssertEqual(model.phase, .readyToInstall)

        model.installAndRelaunchNow()
        XCTAssertEqual(relaunchRequests, 2)
    }

    func testSkippingAnUpdateUsesTheOfferedBuildAndANewOfferReplacesIt() {
        let model = BrowserSoftwareUpdateModel()
        var skippedBuilds: [String] = []

        model.presentUpdate(
            title: "Crest 0.5.1",
            version: "0.5.1",
            build: "501",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("501") }
        )
        XCTAssertEqual(model.updateBuild, "501")
        model.skipUpdate()
        XCTAssertEqual(skippedBuilds, ["501"])
        XCTAssertEqual(model.phase, .idle)

        model.presentUpdate(
            title: "Crest 0.5.2",
            version: "0.5.2",
            build: "502",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("502") }
        )
        XCTAssertEqual(model.updateBuild, "502")
        model.skipUpdate()
        XCTAssertEqual(skippedBuilds, ["501", "502"])
    }

}
