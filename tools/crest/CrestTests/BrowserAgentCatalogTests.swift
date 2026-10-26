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

    func testPrivateCreationValidatesBeforeMutationAndNeverExposesPrivateTabs() async throws {
        let fixture = try BrowserAgentFixture()
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

    func testAWindowOpensOnlyOnceThePersonAgreesAndAgainWithoutAskingWhenTheyLetIt() async throws {
        let fixture = try BrowserAgentFixture()
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

    func testLockedSpacesRedactListingsAndDenyPublicWindowCreation() async throws {
        let fixture = try BrowserAgentFixture()
        fixture.application.browser.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/locked-history")), titled: "Locked history coverage")
        let visible = try await fixture.invoke("search_history", ["query": .string("Locked history coverage")])
        XCTAssertEqual(try visible["entries"]?.decoded(as: [Visit].self).count, 1)
        fixture.application.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
        let before = fixture.application.stackedWindowIDs
        let listing = try await fixture.invoke("list_spaces")
        let spaces = try XCTUnwrap(listing["spaces"]?.decoded(as: [AgentJSON].self))
        let locked = try XCTUnwrap(spaces.first { $0["id"]?.string == fixture.space.id.uuidString })
        XCTAssertEqual(locked["locked"], .bool(true))
        XCTAssertNil(locked["active"])
        XCTAssertNil(locked["symbol"])
        XCTAssertNil(locked["icon"])
        let history = try await fixture.invoke("search_history", ["query": .string("Locked history coverage")])
        XCTAssertEqual(try history["entries"]?.decoded(as: [Visit].self).count, 0)
        for name in ["open_window", "open_blank_window", "open_quick_window"] {
            var arguments: [String: AgentJSON] = ["space": .string(fixture.space.id.uuidString)]
            if name != "open_blank_window" { arguments["url"] = .string("https://example.com/locked") }
            await fixture.assertRefused(name, arguments)
        }
        XCTAssertEqual(fixture.application.stackedWindowIDs, before)
    }
}
