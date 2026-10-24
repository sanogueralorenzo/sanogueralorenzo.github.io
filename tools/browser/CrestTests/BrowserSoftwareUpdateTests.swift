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
        // The packaged default follows the branch (Experimental on a branch
        // build, Development or Stable on main); it must always name a
        // channel the app understands, or updates would fall back silently.
        XCTAssertNotNil(
            (Bundle.main.object(forInfoDictionaryKey: "CrestDefaultUpdateChannel") as? String)
                .flatMap(BrowserSoftwareUpdateChannel.named)
        )
    }

    func testReleaseChannelsMapToTheirSignedFeedsAndSparkleChannels() {
        XCTAssertEqual(BrowserSoftwareUpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.nightly.allowedSparkleChannels, ["nightly"])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.development.allowedSparkleChannels, ["development"])
        XCTAssertEqual(BrowserSoftwareUpdateChannel.experimental.allowedSparkleChannels, ["experimental"])

        // Each product keeps its own feeds whichever engine this test host
        // runs: the dual-engine product reads the main feed from its
        // Info.plist, and WebKit-only installs follow the -webkit feeds.
        let feeds = "https://raw.githubusercontent.com/pauljoda/Crest/updates/"
        let expected: [(channel: BrowserSoftwareUpdateChannel, chromium: String?, webKit: String)] = [
            (.stable, nil, "appcast-webkit.xml"),
            (.nightly, nil, "appcast-webkit.xml"),
            (.development, "appcast-development.xml", "appcast-development-webkit.xml"),
            (.experimental, "appcast-experimental.xml", "appcast-experimental-webkit.xml"),
        ]
        for feed in expected {
            XCTAssertEqual(
                feed.channel.feedURL(for: .chromium)?.absoluteString,
                feed.chromium.map { feeds + $0 },
                feed.channel.name
            )
            XCTAssertEqual(feed.channel.feedURL(for: .webKit)?.absoluteString, feeds + feed.webKit, feed.channel.name)
        }
    }

    func testBundledChannelBecomesTheDefaultUntilTheUserChoosesAnother() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)

        service.channel = .nightly

        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.nightly.name
        )
    }

    func testInstallingAnArtifactFromAnotherChannelAdoptsItsBundledChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)
        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.development.name
        )
    }

    func testUserChoiceSurvivesRelaunchesOfTheSameArtifactChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.nightly.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.development.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .nightly)
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
        let snapshot = try XCTUnwrap(model.sidebarWidgetSnapshot)
        XCTAssertEqual(snapshot.phase, .readyToInstall)
        XCTAssertTrue(snapshot.allowsInstallAndRelaunch)

        model.installAndRelaunchNow()
        XCTAssertEqual(relaunchRequests, 2)
    }

    func testSidebarWidgetDismissesTheExactBuildAndAChangedBuildReappears() async throws {
        let source = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: source)
        var iterator = source.events().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])
        var skippedBuilds: [String] = []

        model.presentUpdate(
            title: "Crest 0.5.1",
            version: "0.5.1",
            build: "501",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("501") }
        )
        let firstEmission = await iterator.next()
        let first = try XCTUnwrap(firstEmission?.first)
        XCTAssertEqual(first.id.instanceID, "501")

        source.perform(.dismissExactUpdate, on: first.id)
        XCTAssertEqual(skippedBuilds, ["501"])
        let dismissed = await iterator.next()
        XCTAssertEqual(dismissed, [])

        model.presentUpdate(
            title: "Crest 0.5.2",
            version: "0.5.2",
            build: "502",
            isInformationOnly: false,
            install: {},
            skip: { skippedBuilds.append("502") }
        )
        let newerEmission = await iterator.next()
        let newer = try XCTUnwrap(newerEmission?.first)
        XCTAssertEqual(newer.id.instanceID, "502")
        XCTAssertNotEqual(newer.id, first.id)
    }

}
