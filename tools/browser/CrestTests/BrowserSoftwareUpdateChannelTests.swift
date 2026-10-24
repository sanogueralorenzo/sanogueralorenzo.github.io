import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateChannelTests: XCTestCase {
    func testUpdatesKeepTheInstalledEngineCompositionOnEveryChannel() {
        XCTAssertNil(BrowserSoftwareUpdateChannel.stable.feedURL(for: .chromium))
        XCTAssertNil(BrowserSoftwareUpdateChannel.nightly.feedURL(for: .chromium))
        for channel in [BrowserSoftwareUpdateChannel.stable, .nightly] {
            XCTAssertEqual(channel.feedURL(for: .webKit)?.lastPathComponent, "appcast-webkit.xml")
        }
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.development.feedURL(for: .chromium)?.lastPathComponent,
            "appcast-development.xml")
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.development.feedURL(for: .webKit)?.lastPathComponent,
            "appcast-development-webkit.xml")
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.experimental.feedURL(for: .chromium)?.lastPathComponent,
            "appcast-experimental.xml")
        XCTAssertEqual(
            BrowserSoftwareUpdateChannel.experimental.feedURL(for: .webKit)?.lastPathComponent,
            "appcast-experimental-webkit.xml")
    }
    func testFinalExperimentalBuildMovesToDevelopmentOnceAndKeepsLaterUserChoices() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("experimental", forKey: BrowserSoftwareUpdateService.channelPreferenceKey)
        preferences.set("experimental", forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey)

        let installed = BrowserSoftwareUpdateService(
            isEnabled: false, preferences: preferences, defaultChannel: .development)
        XCTAssertEqual(installed.channel, .development)
        XCTAssertEqual(
            preferences.string(forKey: BrowserSoftwareUpdateService.channelPreferenceKey), "development")
        installed.channel = .nightly

        let relaunched = BrowserSoftwareUpdateService(
            isEnabled: false, preferences: preferences, defaultChannel: .development)
        XCTAssertEqual(relaunched.channel, .nightly)
    }

}
