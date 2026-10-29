import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativePaletteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_188_800)  // 2026-10-28 12:00 UTC
    private func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    private let remote = ["Crest Browser", "crest browser", "Café", "Cafe", "two   spaces", "next result"]
    private var commands: [PaletteCommand] {
        ShortcutCommand.all.filter(\.offersInPalette).map {
            PaletteCommand(command: $0, title: $0.name, sectionTitle: "Everyday")
        }
    }
    private var settings: [PaletteSettingsPage] {
        [
            PaletteSettingsPage(name: "privacy", title: "Privacy & Security", terms: "blocking cookies history"),
            PaletteSettingsPage(name: "search", title: "Search Provider", terms: "Google Brave"),
        ]
    }

    /// Captured from the Crest C# implementation before it was removed. Compares
    /// complete answers, not merely whether a plausible result is present.
    func testAnswersMatchCrestAcrossRankingCompletionScopesCalculationAndSuggestions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/palette-crest-baseline.json")
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(expected.count, 52)
        for fixture in expected {
            let text = try XCTUnwrap(fixture["text"] as? String)
            let completes = try XCTUnwrap(fixture["completes"] as? Bool)
            let answer = palette(text).answer(question(text, completes: completes))
            let actual = project(answer, text: text, completes: completes)
            XCTAssertEqual(
                actual as NSDictionary, fixture as NSDictionary, "Crest parity: \(text), completion \(completes)")
        }
    }

    func testSuggestionsUseTheGlobalProviderAndStayOffWithoutConsentOrInPrivateWindows() async throws {
        let core = CrestCore()
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Work", tabs: [])]), core: core)
        let borrowed = try XCTUnwrap(
            browser.makeTemporaryWindowStore(
                in: BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(browser.shownSpace))))
        let privateBrowser = BrowserStore.privateBrowsing(core: core)
        func ask(_ target: BrowserStore) async throws -> PaletteAnswer {
            let answer = await core.palette(
                PaletteSuggestions(
                    windowID: target.windowID, text: "crest & browser", commands: [], settingsPages: [],
                    remote: remote, scope: nil, allowsCompletion: true))
            return try XCTUnwrap(answer)
        }
        let initial = try await ask(browser)
        XCTAssertNil(initial.suggestionAddress)
        for provider in SearchProvider.all {
            try core.send(
                SetAppPreferences(
                    workspaceID: browser.family.workspaceID,
                    preferences: AppPreferences(
                        translationLanguage: "en", searchProvider: provider, translateAutomatically: false,
                        excludedTranslationLanguages: [], searchSuggestionsEnabled: true)))
            for target in [browser, borrowed, privateBrowser] {
                let answer = try await ask(target)
                let row = try XCTUnwrap(answer.groups.flatMap(\.rows).first { $0.kind == .search })
                XCTAssertEqual(row.provider, provider)
                XCTAssertEqual(
                    row.address,
                    try core.query(
                        ResolveAddress(workspaceID: target.family.workspaceID, spaceID: nil, input: "crest & browser")
                    ).url)
                XCTAssertEqual(answer.suggestionAddress != nil, !target.isPrivateBrowsing)
                XCTAssertEqual(answer.groups.contains { $0.section == .searchSuggestions }, !target.isPrivateBrowsing)
            }
        }
        try core.send(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: .default))
        let disabled = try await ask(browser)
        XCTAssertNil(disabled.suggestionAddress)
        XCTAssertFalse(disabled.groups.contains { $0.section == .searchSuggestions })
    }

    func testClearingHistoryImmediatelyRemovesItsRowsAndCompletion() throws {
        let core = CrestCore()
        let entry = HistoryEntryState(url: URL(string: "https://news.example.org/today")!, title: "Today")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Work", tabs: [], history: [entry])]), core: core)
        let asking = PaletteSuggestions(
            windowID: browser.windowID, text: "news", commands: [], settingsPages: [], remote: [], scope: nil,
            allowsCompletion: true)
        XCTAssertEqual(core.paletteNow(asking)?.completion?.suffix, ".example.org")
        try core.send(
            ClearHistory(workspaceID: browser.family.workspaceID, spaceID: browser.selectedSpaceID, range: .allTime))
        let answer = try XCTUnwrap(core.paletteNow(asking))
        XCTAssertNil(answer.completion)
        XCTAssertFalse(answer.groups.flatMap(\.rows).contains { $0.kind == .history })
    }

    func testTextMatchingKeepsTermsBoundariesInitialsAndUnicodeFolding() {
        XCTAssertEqual(PaletteQuery("field notes").score("Field Notes"), 850)
        XCTAssertEqual(PaletteQuery("notes").score("Field Notes"), 700)
        XCTAssertEqual(PaletteQuery("otes").score("Field Notes"), 300)
        XCTAssertEqual(PaletteQuery("tsv").abbreviates("Toggle Split View"), 250)
        XCTAssertEqual(PaletteQuery("tgv").abbreviates("Toggle Split View"), 150)
        XCTAssertNil(PaletteQuery("field nowhere").score("Field Notes"))
        XCTAssertEqual(PaletteQuery("ςίγμα").score("Σίγμα notes"), 1_000)
        XCTAssertEqual(PaletteQuery("𐐨").score("𐐀 Test"), 1_000)
        XCTAssertTrue(PaletteQuery("field\t notes").prefixes("Field  Notes"))
    }

    func testCalculationIsBoundedAndDoesNotEvaluateWordsOrBareNumbers() {
        for (expression, expected) in [
            ("2+2*3", "8"), ("(1.5 + 2.5) ^ 2 / 4", "4"), ("10 % 4 − 1", "1"), ("2^3^2", "512"), ("-2^2", "4"),
            ("-0", "0"), ("10^20", "1E+20"),
        ] {
            XCTAssertEqual(PaletteCalculation.read(expression)?.answer, expected, expression)
        }
        for expression in [
            "42", "2/0", "2 apples", "pow(2,3)", "1e3", "2..3+4",
            String(repeating: "(", count: 33) + "1+2" + String(repeating: ")", count: 33),
            String(repeating: "1+", count: 65) + "1",
        ] {
            XCTAssertNil(PaletteCalculation.read(expression), expression)
        }
    }

    func testCompletionPreservesSchemePortsPathCaseAndDeterministicTies() throws {
        let candidate = try XCTUnwrap(
            PaletteAddressCandidate("http://www.example.org:8080/Docs/Start?q=1#part", source: 3, date: now))
        XCTAssertEqual(
            candidate.completing(try XCTUnwrap(PaletteTypedAddress("ex")))?.opens, "http://www.example.org:8080/")
        XCTAssertEqual(
            candidate.completing(try XCTUnwrap(PaletteTypedAddress("example.org:8080/D")))?.text,
            "example.org:8080/Docs/")
        XCTAssertNil(candidate.completing(try XCTUnwrap(PaletteTypedAddress("example.org:8080/d"))))
        XCTAssertNil(candidate.completing(try XCTUnwrap(PaletteTypedAddress("https://ex"))))
        XCTAssertNil(PaletteTypedAddress("ex ample"))
        XCTAssertNil(PaletteTypedAddress("example.org?query"))
        XCTAssertNil(PaletteAddressCandidate("https://user:password@example.org", source: 3, date: now))
    }

    private func question(_ text: String, completes: Bool = true) -> PaletteSuggestions {
        PaletteSuggestions(
            windowID: id(100), text: text, commands: commands, settingsPages: settings, remote: remote, scope: nil,
            allowsCompletion: completes)
    }
    private func palette(_ text: String = "") -> NativePalette {
        NativePalette(
            space: makeSpace(), shownTabID: id(11), isPrivate: false,
            spaces: [PaletteSpaceChoice(id: id(3), name: "Side Projects")], now: now,
            provider: .google, suggests: true,
            resolution: try? CrestCore.answer(ResolveAddress(workspaceID: nil, spaceID: nil, input: text)))
    }
    private func makeSpace() -> PaletteSpaceSnapshot {
        func folder(_ value: Int, _ title: String, _ parent: Int? = nil) -> FolderState {
            FolderState(
                id: id(value), location: .saved, title: title, color: nil, parentID: parent.map(id), isCollapsed: false,
                collapseModifiedAt: nil, orderAnchorTabID: nil, source: nil, liveOptions: nil, gitHubOptions: .default,
                displayColor: FolderState.defaultColor)
        }
        func tab(
            _ value: Int, _ title: String, _ url: String, _ placement: TabPlacement, hours: Int = 1, folder: Int? = nil,
            saved: String? = nil
        ) -> TabState {
            TabState(
                id: id(value), title: title, url: url, nativeContent: nil, savedURL: saved, symbol: "globe",
                faviconURL: nil, iconAccent: nil, storedIconMode: nil, placement: placement, folderID: folder.map(id),
                splitGroupID: nil, lastActivatedAt: now.addingTimeInterval(-Double(hours) * 3_600),
                positionModifiedAt: nil, customTitle: nil, titleModifiedAt: nil, iconMode: .automatic,
                displayTitle: title, isAwayFromSavedAddress: false, pageIconIsCurrent: false, surface: .webPage,
                nativeView: nil)
        }
        func entry(_ value: Int, _ url: String, _ title: String, _ first: Int, _ last: Int, _ visits: Int)
            -> HistoryEntryState
        {
            HistoryEntryState(
                id: id(value), url: url, title: title, firstVisitedAt: now.addingTimeInterval(-Double(first) * 86_400),
                lastVisitedAt: now.addingTimeInterval(-Double(last) * 86_400), visitCount: visits)
        }
        return PaletteSpaceSnapshot(
            folders: [folder(20, "Projects"), folder(21, "Field notes", 20)],
            tabs: [
                tab(10, "Field notes", "https://example.org/notes", .current),
                tab(11, "Elsewhere", "https://elsewhere.net/", .current),
                tab(12, "Amazon Orders", "https://www.amazon.de/gp/order-history", .saved, hours: 7, folder: 21),
                tab(
                    13, "Swift docs", "https://swift.org/new", .pinned, hours: 12,
                    saved: "https://swift.org/documentation"),
                tab(14, "Σίγμα notes", "https://greek.example/", .current, hours: 36),
            ],
            history: [
                entry(30, "http://www.example.org/notes", "Field notes", 30, 1, 20),
                entry(31, "https://news.example.org/today", "Today", 20, 2, 6),
                entry(32, "https://www.amazon.de/gp/orders", "Your Orders", 400, 2, 18),
                entry(33, "https://swift.org/documentation", "Swift docs", 30, 1, 60),
            ])
    }

    private func project(_ answer: PaletteAnswer, text: String, completes: Bool) -> [String: Any] {
        func optional<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let groups = answer.groups.map { group in
            [
                "section": group.section.name,
                "rows": group.rows.map { row in
                    [
                        "kind": row.kind.name, "title": row.title, "subtitle": row.subtitle, "symbol": row.symbol,
                        "subjectID": optional(row.subjectID?.uuidString.lowercased()),
                        "tabID": optional(row.tabID?.uuidString.lowercased()), "address": optional(row.address),
                        "command": optional(row.command?.name), "provider": optional(row.provider?.name),
                        "settingsPage": optional(row.settingsPage), "scope": optional(row.scope?.name),
                        "reason": optional(row.reason?.name),
                    ]
                },
            ] as [String: Any]
        }
        return [
            "text": text, "completes": completes, "groups": groups,
            "completion": optional(
                answer.completion.map { ["typed": $0.typed, "suffix": $0.suffix, "accepted": $0.accepted] }),
            "suggestionAddress": optional(answer.suggestionAddress),
            "offeredScope": optional(answer.offeredScope?.name),
            "entry": optional(answer.entry.map { ["scope": $0.scope.name, "text": $0.text] }),
        ]
    }
}
