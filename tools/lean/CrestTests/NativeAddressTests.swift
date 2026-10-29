import Foundation
import XCTest

@testable import Crest

final class NativeAddressTests: XCTestCase {
    private struct Baseline: Decodable {
        struct Row: Decodable {
            let input: String
            let provider: String
            let url: String?
            let query: String?
            let loading: String?
        }
        struct History: Decodable {
            let input: String
            let normalized: String?
        }
        let rows: [Row]
        let history: [History]
    }
    private func baseline() throws -> Baseline {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/native-address-crest-baseline.json")
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }
    private func portable(_ url: String?) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        return url?.replacingOccurrences(of: home, with: "${HOME}")
    }
    func testTypedAndLoadedAddressesMatchActualCrestForEveryProvider() throws {
        let rows = try baseline().rows
        XCTAssertEqual(rows.count, 436)
        for row in rows {
            let provider = try XCTUnwrap(SearchProvider.named(row.provider))
            let answer = BrowserAddress.resolve(row.input, provider: provider)
            let context = "\(row.provider): \(row.input.prefix(100))"
            XCTAssertEqual(portable(answer.url), row.url, context)
            XCTAssertEqual(answer.searchQuery, row.query, context)
            XCTAssertEqual(portable(BrowserAddress.loading(row.input, provider: provider)), row.loading, context)
        }
    }
    func testVisitedAddressesMatchCrestAndFragmentsMatchOnlyForWebPages() throws {
        let rows = try baseline().history
        XCTAssertEqual(rows.count, 109)
        for row in rows {
            XCTAssertEqual(BrowserWebAddress.normalized(row.input), row.normalized, String(row.input.prefix(100)))
        }
        XCTAssertTrue(PageAddress.samePage("https://example.com/#one", "https://example.com/#two"))
        XCTAssertFalse(PageAddress.samePage("file:///tmp/page#one", "file:///tmp/page#two"))
        XCTAssertFalse(PageAddress.samePage("https://example.com/Café", "https://example.com/Cafe\u{301}"))
        for host in ["[:::]", "[1::2::3]", "[1:2]", "[not-ip]", "foo..com"] {
            XCTAssertEqual(BrowserAddress.resolve(host).searchQuery, host)
        }
    }
    @MainActor
    func testNativeTabNavigationResolvesOnceWithGlobalSearchAndPreservesItsIdentity() throws {
        let core = try CrestCore(
            configuration: AppConfiguration(storageDirectory: nil, platform: .desktop, importNames: nil))
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Work", tabs: [])]), core: core)
        defer { browser.family.close() }
        let settings = try XCTUnwrap(browser.openSettings())
        XCTAssertFalse(browser.navigateSelectedTab(to: " "))
        XCTAssertFalse(browser.navigateSelectedTab(to: String(repeating: "a", count: 4097)))
        XCTAssertNotNil(browser.shownTab?.nativeContent)
        var preferences = AppPreferences.default
        preferences.searchProvider = .bing
        try core.send(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: preferences))
        XCTAssertTrue(browser.navigateSelectedTab(to: "  café & browser  "))
        XCTAssertEqual(browser.shownTab?.id, settings)
        XCTAssertNil(browser.shownTab?.nativeContent)
        XCTAssertEqual(browser.shownTab?.url, "https://www.bing.com/search?q=caf%C3%A9%20%26%20browser")
        let space = try XCTUnwrap(browser.shownSpace)
        let source = BrowserTabRuntimeAssignment(tabID: settings, spaceID: space.id, profileID: space.profileID)
        let links = BrowserLinkDestinationHost(browser: browser)
        let search = try XCTUnwrap(links.selectionSearch(for: "  selected & text  ", from: source))
        XCTAssertEqual(search.engineTitle, "Bing")
        XCTAssertEqual(search.url.absoluteString, "https://www.bing.com/search?q=selected%20%26%20text")
        XCTAssertNil(links.selectionSearch(for: "  ", from: source))
        XCTAssertNil(
            links.selectionSearch(
                for: "text", from: BrowserTabRuntimeAssignment(tabID: settings, spaceID: space.id, profileID: UUID())))
        XCTAssertFalse(browser.navigateSelectedTab(to: "https://example.com/new"))
        XCTAssertEqual(browser.shownTab?.url, "https://www.bing.com/search?q=caf%C3%A9%20%26%20browser")
    }
}
