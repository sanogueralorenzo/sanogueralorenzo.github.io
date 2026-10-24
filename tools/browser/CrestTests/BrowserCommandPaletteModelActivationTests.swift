import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteModelActivationTests: XCTestCase {
    func testActivationCarriesExactAssignmentsAndRejectsAStaleSource() throws {
        let sourceTab = TabState.Seed.startPage(
            id: uuid(0x11),
            lastActivatedAt: fixedDate
        )
        let targetTab = TabState.Seed(
            id: uuid(0x12),
            title: "Target",
            url: URL(fileURLWithPath: "/palette-target"),
            placement: .current,
            lastActivatedAt: fixedDate
        )
        let space = SpaceState.Seed(
            id: uuid(0x21),
            profileID: uuid(0x31),
            name: "Palette",
            symbol: "command",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab, targetTab]
        )
        var sourceIsAvailable = false
        var capturedSource: BrowserTabRuntimeAssignment?
        var capturedTarget: BrowserTabRuntimeAssignment?
        var dismissalCount = 0
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: sourceTab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser,
            space: browser.spaceModel(space.id),
            selectedTabID: sourceTab.id,
            initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in sourceIsAvailable },
            selectTab: { source, target in
                capturedSource = source
                capturedTarget = target
                return true
            },
            openURL: { _, _, _ in false },
            dismiss: { dismissalCount += 1 }
        )
        let targetResult = try XCTUnwrap(model.items.first { $0.row.tabID == targetTab.id }?.row)

        model.activate(targetResult)
        XCTAssertNil(capturedSource)
        XCTAssertNil(capturedTarget)
        XCTAssertEqual(dismissalCount, 0)

        sourceIsAvailable = true
        model.activate(targetResult)

        XCTAssertEqual(
            capturedSource,
            BrowserTabRuntimeAssignment(
                tabID: sourceTab.id,
                spaceID: space.id,
                profileID: space.profileID
            )
        )
        XCTAssertEqual(
            capturedTarget,
            BrowserTabRuntimeAssignment(
                tabID: targetTab.id,
                spaceID: space.id,
                profileID: space.profileID
            )
        )
        XCTAssertEqual(dismissalCount, 1)
    }

    func testSuggestionsStayOffUntilTheSpaceOptsIn() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: false)
        let recorder = SuggestionRecorder(results: ["remote result"])
        let model = makeModel(fixture: fixture, recorder: recorder)

        model.query = "crest browser"
        await model.waitForPendingResults()

        let queries = await recorder.queries
        XCTAssertTrue(queries.isEmpty)
        XCTAssertFalse(model.groups.contains { $0.section == .searchSuggestions })
    }

    func testPrivateBrowsingNeverSendsAnOptedInQuery() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: true)
        let recorder = SuggestionRecorder(results: ["remote result"])
        let model = makeModel(
            fixture: fixture,
            isPrivateBrowsing: true,
            recorder: recorder
        )

        model.query = "private words"
        await model.waitForPendingResults()

        let queries = await recorder.queries
        XCTAssertTrue(queries.isEmpty)
        XCTAssertFalse(model.groups.contains { $0.section == .searchSuggestions })
    }

    func testOptedInSuggestionsCancelAndIgnoreStaleResponsesWithoutReorderingSelection() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: true)
        let recorder = SuggestionRecorder(
            resultsByQuery: [
                "first words": ["stale suggestion"],
                "latest words": ["latest suggestion"],
            ],
            delayByQuery: ["first words": .milliseconds(80)]
        )
        let model = makeModel(fixture: fixture, recorder: recorder)

        model.query = "first words"
        await Task.yield()
        model.query = "latest words"
        await model.waitForPendingResults()

        XCTAssertEqual(
            model.groups.first { $0.section == .searchSuggestions }?.items.map(\.row.title),
            ["latest suggestion"]
        )
        XCTAssertFalse(model.items.contains { $0.row.title == "stale suggestion" })
        XCTAssertEqual(model.selectedResultIndex, 0)
    }

    func testSuggestionNetworkConfigurationCarriesNoCookiesOrSharedCache() {
        let configuration = BrowserSearchSuggestionClient.sessionConfiguration

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 5)
    }

    private func makePaletteFixture(
        searchSuggestionsEnabled: Bool
    ) -> (space: SpaceState.Seed, sourceTab: TabState.Seed) {
        let sourceTab = TabState.Seed.startPage(
            id: uuid(0x41),
            lastActivatedAt: fixedDate
        )
        let localTab = TabState.Seed(
            id: uuid(0x42),
            title: "Local Crest tab",
            url: URL(string: "https://example.com/crest"),
            placement: .current,
            lastActivatedAt: fixedDate
        )
        var preferences = BrowsingPreferences.seeded
        preferences.followsDefaultSuggestions = false
        preferences.searchSuggestionsEnabled = searchSuggestionsEnabled
        let space = SpaceState.Seed(
            id: uuid(0x51),
            profileID: uuid(0x61),
            name: "Suggestions",
            symbol: "magnifyingglass",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab, localTab],
            browsingPreferences: preferences
        )
        return (space, sourceTab)
    }

    private func makeModel(
        fixture: (space: SpaceState.Seed, sourceTab: TabState.Seed),
        isPrivateBrowsing: Bool = false,
        recorder: SuggestionRecorder
    ) -> BrowserCommandPaletteModel {
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [fixture.space]), showing: fixture.space.id,
            tabs: [fixture.space.id: fixture.sourceTab.id],
            browsingMode: isPrivateBrowsing ? .privateBrowsing : .standard)
        return BrowserCommandPaletteModel(
            browser: browser,
            space: browser.spaceModel(fixture.space.id),
            selectedTabID: fixture.sourceTab.id,
            initialQuery: "",
            commands: nil,
            suggestionDebounce: .zero,
            fetchSuggestions: { address in
                await recorder.suggestions(from: address)
            },
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in false },
            openURL: { _, _, _ in false },
            dismiss: {}
        )
    }

    private var fixedDate: Date {
        Date(timeIntervalSinceReferenceDate: 600)
    }

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x4D, 0x4F, 0x44, finalByte
            ))
    }
}

private actor SuggestionRecorder {
    private(set) var queries: [String] = []
    private let resultsByQuery: [String: [String]]
    private let delayByQuery: [String: Duration]

    init(
        results: [String] = [],
        resultsByQuery: [String: [String]] = [:],
        delayByQuery: [String: Duration] = [:]
    ) {
        self.resultsByQuery = resultsByQuery.merging(["*": results]) { current, _ in current }
        self.delayByQuery = delayByQuery
    }

    /// The suggestions for the query the engine's address carries.
    func suggestions(from address: URL) async -> [String] {
        let query =
            URLComponents(url: address, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            ?? ""
        queries.append(query)
        if let delay = delayByQuery[query] {
            try? await Task.sleep(for: delay)
        }
        return resultsByQuery[query] ?? resultsByQuery["*"] ?? []
    }
}
