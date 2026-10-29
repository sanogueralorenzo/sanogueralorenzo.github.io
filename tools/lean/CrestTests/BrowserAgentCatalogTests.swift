import AppKit
import XCTest

@testable import Crest

/// Tools share the core's live permission boundary and never expose private tabs.
@MainActor
final class BrowserAgentCatalogTests: XCTestCase {
    // MARK: - Types

    private struct Visit: Decodable {
        let title: String
        let url: String
        let lastVisitedAt: String
    }

    // MARK: - Actions - Catalogs

    func testWindowToolsPreserveTheRequestedSpaceAndSavedTabIdentity() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        let before = fixture.application.stackedWindowIDs
        await fixture.assertRefused("open_window", ["url": .string("file:///private/tmp/test")])
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        let opening = try await fixture.invoke(
            "open_window",
            [
                "space": .string(fixture.space.id.uuidString), "url": .string("https://example.com/window"),
            ])
        let windowID = try XCTUnwrap(opening["windowID"]?.string.flatMap(UUID.init(uuidString:)))
        defer { fixture.windows.window(for: windowID)?.close() }
        XCTAssertEqual(opening["spaceID"]?.string, fixture.space.id.uuidString)
        XCTAssertNotNil(opening["tabID"])
        let listed = try await fixture.invoke("list_tabs")
        let created = try XCTUnwrap(
            listed["tabs"]?.decoded(as: [[String: AgentJSON]].self).first {
                $0["id"]?.string == opening["tabID"]?.string
            })
        XCTAssertEqual(created["inUse"], .bool(true))
        let saved = try addSavedTab(to: fixture)
        let count = fixture.space.tabs.models.count
        let shown = try await fixture.invoke("show_tab", ["tab": .string(saved.id.uuidString)])
        XCTAssertEqual(shown["tab"]?["id"]?.string, saved.id.uuidString)
        XCTAssertEqual(fixture.space.tabs.models.count, count)
        let blank = try await fixture.invoke("open_blank_window", ["space": .string(fixture.space.id.uuidString)])
        XCTAssertEqual(blank["spaceID"], opening["spaceID"])
        let blankID = try XCTUnwrap(blank["windowID"]?.string.flatMap(UUID.init(uuidString:)))
        defer { fixture.windows.window(for: blankID)?.close() }
        XCTAssertNotNil(fixture.windows.window(for: blankID))
    }

    func testLiveHistoryAndProvidersRespectRevocationAndSearchBeforeLimiting() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        let catalog = try await fixture.invoke("list_search_providers")
        XCTAssertNotNil(catalog["defaultProvider"])
        let url = try XCTUnwrap(URL(string: "https://docs.example.com/older"))
        fixture.application.browser.seedVisit(to: url, titled: "Older matching visit")
        for index in 0..<30 {
            fixture.application.browser.seedVisit(
                to: try XCTUnwrap(URL(string: "https://example.com/new/\(index)")), titled: "New visit")
        }
        let newest = try await fixture.invoke("search_history", ["limit": .number(25)])
        XCTAssertEqual(try newest["entries"]?.decoded(as: [Visit].self).count, 25)
        let found = try await fixture.invoke(
            "search_history", ["query": .string("Older matching"), "limit": .number(25)])
        let visits = try XCTUnwrap(found["entries"]?.decoded(as: [Visit].self))
        XCTAssertEqual(visits.map(\.url), ["https://docs.example.com/older"])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: try XCTUnwrap(visits.first?.lastVisitedAt)))
        let excluded = try await fixture.invoke("search_history", ["domain": .string("other.example.com")])
        XCTAssertEqual(try excluded["entries"]?.decoded(as: [Visit].self).count, 0)
        await fixture.assertRefused("search_history", ["limit": .number(1001)])
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        let revoked = try await fixture.invoke("search_history")
        XCTAssertEqual(try revoked["entries"]?.decoded(as: [Visit].self).count, 0)
        await fixture.assertRefused("list_search_providers", ["space": .string(fixture.space.id.uuidString)])
    }

    func testPrivateCreationValidatesBeforeMutationAndNeverExposesPrivateTabs() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        let before = fixture.application.stackedWindowIDs
        await fixture.assertRefused("open_private_window", ["url": .string("javascript:alert(1)")])
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        let answer = try await fixture.invoke("open_private_window", ["url": .string("https://example.com/private")])
        defer { fixture.application.closePrivateBrowsingWindow() }
        XCTAssertNotNil(answer["windowID"])
        XCTAssertNil(answer["tabID"])
        XCTAssertNil(answer["spaceID"])
        let tab = try XCTUnwrap(fixture.application.privateBrowser.shownTab)
        XCTAssertEqual(tab.url, "https://example.com/private")
        // Private browsing the person already has open never takes an agent's address.
        let privateTabs = try XCTUnwrap(fixture.application.privateBrowser.shownSpace).tabs.models.count
        await fixture.assertRefused("open_private_window", ["url": .string("https://example.com/second")])
        _ = try await fixture.invoke("open_private_window")
        XCTAssertEqual(try XCTUnwrap(fixture.application.privateBrowser.shownSpace).tabs.models.count, privateTabs)
        let listed = try await fixture.invoke("list_tabs")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(listed), as: UTF8.self).contains(tab.id.uuidString))
        await fixture.assertRefused("show_tab", ["tab": .string(tab.id.uuidString)])
        fixture.application.privateBrowser.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/private")), titled: "Private history coverage")
        XCTAssertTrue(
            try XCTUnwrap(fixture.application.privateBrowser.shownSpace).history.entries.contains {
                $0.url == "https://example.com/private"
            })
        let history = try await fixture.invoke("search_history", ["query": .string("example.com/private")])
        XCTAssertEqual(try history["entries"]?.decoded(as: [Visit].self).count, 0)
        try fixture.core.send(SetAgents(isOn: false))
        await fixture.assertRefused("open_private_window")
    }

    func testShowingSavedTabWithoutAnOpenWindowKeepsItsIdentity() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        XCTAssertNil(fixture.windows.activeBrowserWindow)
        let saved = try addSavedTab(to: fixture)
        let count = fixture.space.tabs.models.count
        let shown = try await fixture.invoke("show_tab", ["tab": .string(saved.id.uuidString)])
        XCTAssertEqual(shown["tab"]?["id"]?.string, saved.id.uuidString)
        XCTAssertEqual(fixture.space.tabs.models.count, count)
        let window = try XCTUnwrap(fixture.windows.activeBrowserWindow)
        window.close()
    }

    func testAWindowOpensOnlyOnceThePersonAgreesAndAgainWithoutAskingWhenTheyLetIt() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        let before = fixture.application.stackedWindowIDs
        fixture.answers.windows = .declined
        await fixture.assertRefused("open_window", ["space": .string(fixture.space.id.uuidString)])
        await fixture.assertRefused("open_private_window")
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        XCTAssertFalse(fixture.windows.isOpen(.private))
        XCTAssertEqual(fixture.answers.openings.map(\.kind), [.window, .privateWindow])
        XCTAssertEqual(fixture.answers.openings.first?.agentName, "Test")
        fixture.answers.windows = .whileConnected
        let first = try await fixture.invoke("open_blank_window", ["space": .string(fixture.space.id.uuidString)])
        let second = try await fixture.invoke("open_blank_window", ["space": .string(fixture.space.id.uuidString)])
        defer {
            for answer in [first, second] {
                if let id = answer["windowID"]?.string.flatMap(UUID.init(uuidString:)) {
                    fixture.windows.window(for: id)?.close()
                }
            }
        }
        XCTAssertEqual(fixture.answers.openings.count, 3)
        // A private window is asked about every time.
        fixture.answers.windows = .declined
        await fixture.assertRefused("open_private_window")
        XCTAssertEqual(fixture.answers.openings.last?.kind, .privateWindow)
        XCTAssertFalse(fixture.windows.isOpen(.private))
    }

    func testDeniedSpacesCannotOpenPublicWindows() async throws {
        let fixture = try BrowserAgentFixture()
        defer { fixture.close() }
        try fixture.core.send(AllowAgentSpace(spaceID: fixture.space.id, allowed: false))
        let before = fixture.application.stackedWindowIDs
        for name in ["open_window", "open_blank_window"] {
            var arguments: [String: AgentJSON] = ["space": .string(fixture.space.id.uuidString)]
            if name != "open_blank_window" { arguments["url"] = .string("https://example.com/denied") }
            await fixture.assertRefused(name, arguments)
        }
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
        await fixture.assertRefused("open_window")
    }
    private func addSavedTab(to fixture: BrowserAgentFixture) throws -> TabStateModel {
        let browser = fixture.application.browser
        let url = try XCTUnwrap(URL(string: "https://saved.example.com"))
        let id = try XCTUnwrap(browser.openNewTab(url: url))
        browser.saveTab(id)
        return try XCTUnwrap(fixture.space.tabs.model(id))
    }

}
