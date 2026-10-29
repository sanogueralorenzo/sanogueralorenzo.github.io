import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativeImportFlowTests: XCTestCase {
    private func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
    private func tab(_ number: Int, _ url: String, _ placement: TabPlacement = .current) -> TabState.Seed {
        TabState.Seed(id: id(number), title: url, url: URL(string: url), placement: placement)
    }
    private func sources() -> [SpaceState] {
        BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(
                    id: id(100), name: "ＲéAding",
                    tabs: [
                        tab(101, "https://article.example/#part"), tab(102, "https://pin.example/a", .pinned),
                        tab(103, "https://pin.example/b", .pinned),
                    ]),
                SpaceState.Seed(
                    id: id(200), name: "Travel",
                    tabs: [tab(201, "https://travel.example/a"), tab(202, "https://travel.example/b")]),
            ])
        ).snapshot.spaces
    }

    /// The same transition sequence captured before deleting Crest's C# flow.
    /// Compares queue state, all review choices/analysis and aggregated installs.
    func testTransitionsAndReviewMatchCrestExactly() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/import-crest-baseline.json")
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])
        let core = CrestCore()
        let held =
            [tab(10, "https://article.example/", .saved)]
            + (0..<12).map { tab(20 + $0, "https://kept.example/\($0)", .pinned) }
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(id: id(1), name: "Reading", tabs: held)]), core: core)
        var index = 0
        func send(_ name: String, _ intent: some BrowserImportIntent) throws {
            var failure: String?
            do { try core.send(intent) } catch NativeBrowserImport.Failure.busy { failure = "BrowserImportBusy" }
            let state = try XCTUnwrap(core.state.importFlow)
            XCTAssertEqual(
                project(state, action: name, error: failure) as NSDictionary, expected[index] as NSDictionary,
                "Crest import parity: \(name)")
            index += 1
        }
        try send("start", StartBrowserImport(workspaceID: browser.family.workspaceID))
        try send("offer", OfferImportSources(installed: [.chrome, .arc]))
        try send("chooseArc", ToggleImportSource(source: .arc))
        try send("chooseChrome", ToggleImportSource(source: .chrome))
        try send("continue", ContinueImport())
        try send("staleReview", ReviewImport(source: .arc, spaces: [], extensions: nil, leftOut: nil, title: nil))
        try send("busy", ToggleImportSource(source: .arc))
        try send("readFailed", FailImport(source: .chrome, reason: .read, detail: "Unreadable"))
        try send("retry", ContinueImport())
        try send(
            "review",
            ReviewImport(
                source: .chrome, spaces: sources(),
                extensions: [
                    ImportSpaceExtensions(
                        spaceID: id(100),
                        extensions: [
                            ImportExtension(extensionID: "aaa", name: "First", iconPath: "first.png"),
                            ImportExtension(extensionID: "aaa", name: "Repeated", iconPath: nil),
                            ImportExtension(extensionID: "bbb", name: "Second", iconPath: nil),
                        ]),
                    ImportSpaceExtensions(
                        spaceID: id(200),
                        extensions: [ImportExtension(extensionID: "aaa", name: "First", iconPath: nil)]),
                ], leftOut: [], title: "Custom Browser"))
        try send("includeDuplicate", IncludeImportTabs(sourceSpaceID: id(100), tabIDs: [id(101)], included: true))
        try send("place", PlaceImportTab(sourceSpaceID: id(200), tabID: id(201), placement: .pinned))
        try send(
            "customize",
            CustomizeImportSpace(sourceSpaceID: id(200), customization: SpaceCustomization(name: "  Trips  ")))
        try send("excludeTab", IncludeImportTabs(sourceSpaceID: id(200), tabIDs: [id(202)], included: false))
        try send(
            "excludeExtension", IncludeImportExtension(sourceSpaceID: id(100), extensionID: "aaa", included: false))
        try send("excludeSpace", IncludeImportSpace(sourceSpaceID: id(200), included: false))
        try send("includeSpace", IncludeImportSpace(sourceSpaceID: id(200), included: true))
        try send("show", ShowImportSpace(sourceSpaceID: id(200)))
        try send("begin", BeginImportCommit())
        try send("commitFailed", FailImport(source: .chrome, reason: .import, detail: "No room"))
        try send("beginAgain", BeginImportCommit())
        try send("finish", FinishImportCommit())
        try send("cancelRead", CancelImportRead())
        XCTAssertEqual(index, expected.count)
    }

    func testQueueCommitsBothBrowsersAndKeepsPreviewAndCommitChoicesTogether() throws {
        let core = CrestCore()
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Existing", tabs: [])]), core: core)
        try core.send(StartBrowserImport(workspaceID: browser.family.workspaceID))
        try core.send(OfferImportSources(installed: [.arc, .chrome]))
        try core.send(ToggleImportSource(source: .chrome))
        try core.send(ToggleImportSource(source: .arc))
        try core.send(ContinueImport())
        for (index, source) in [ImportSource.arc, .chrome].enumerated() {
            XCTAssertEqual(core.state.importFlow?.source, source)
            try core.send(
                ReviewImport(source: source, spaces: [sources()[index]], extensions: [], leftOut: [], title: nil))
            let preview = try browser.reviewedImportPreview()
            XCTAssertNotNil(preview.space(id: sources()[index].id))
            try core.send(BeginImportCommit())
            XCTAssertThrowsError(try core.send(IncludeImportSpace(sourceSpaceID: sources()[index].id, included: false)))
            try browser.importReviewedSpaces()
            try core.send(FinishImportCommit())
        }
        XCTAssertEqual(browser.spaceModels.map { $0.settings.name }, ["Existing", "ＲéAding", "Travel"])
        XCTAssertEqual(core.state.importFlow?.step, .complete)
        XCTAssertNil(core.state.importFlow?.review)
        XCTAssertEqual(core.state.importFlow?.summary, ImportSummary(tabCount: 2, spaceCount: 1))
    }

    func testSpaceCapacityAndEmptyReviewAreEnforcedWithoutDroppingChoices() throws {
        let core = CrestCore()
        let spaces = (0..<CapacityLimits.current.spaces).map {
            SpaceState.Seed(name: $0 == 0 ? "Reading" : "Kept \($0)", tabs: [])
        }
        let browser = BrowserStore(seed: SessionState.Seed(spaces: spaces), core: core)
        try begin(core, browser)
        try core.send(ReviewImport(source: .chrome, spaces: sources(), extensions: [], leftOut: [], title: nil))
        let review = try XCTUnwrap(core.state.importFlow?.review)
        XCTAssertEqual(review.newSpaceCapacity, 0)
        XCTAssertNotNil(review.spaces[0].destinationID)
        XCTAssertFalse(review.spaces[1].included)
        try core.send(ChooseImportDestination(sourceSpaceID: id(100), destinationSpaceID: nil))
        try core.send(IncludeImportSpace(sourceSpaceID: id(200), included: true))
        XCTAssertEqual(core.state.importFlow?.review, review)
        try core.send(IncludeImportSpace(sourceSpaceID: id(100), included: false))
        XCTAssertThrowsError(try core.send(BeginImportCommit()))
        XCTAssertEqual(core.state.importFlow?.phase, .reviewing)
        XCTAssertTrue(core.state.importFlow?.review?.spaces.allSatisfy { !$0.included } == true)
    }

    func testDuplicateSourcesAndMalformedSplitRunsAreRefusedAtomically() throws {
        let core = CrestCore()
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "Existing", tabs: [])]), core: core)
        try begin(core, browser)
        let before = core.state.importFlow
        let source = sources()[0]
        XCTAssertThrowsError(
            try core.send(
                ReviewImport(source: .chrome, spaces: [source, source], extensions: [], leftOut: [], title: nil)))
        XCTAssertEqual(core.state.importFlow, before)
        let group = UUID()
        var first = tab(300, "https://one.example")
        var second = tab(301, "https://two.example")
        first.splitGroupID = group
        second.splitGroupID = group
        let valid = BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(name: "Split", tabs: [first, second, tab(302, "https://other.example")])
            ])
        ).snapshot.spaces[0]
        let malformed = SpaceState(
            id: valid.id, profileID: valid.profileID, settings: valid.settings, folders: valid.folders,
            tabs: [valid.tabs[0], valid.tabs[2], valid.tabs[1]], archivedTabs: valid.archivedTabs,
            history: valid.history, sidebar: valid.sidebar)
        XCTAssertThrowsError(
            try core.send(ReviewImport(source: .chrome, spaces: [malformed], extensions: [], leftOut: [], title: nil)))
        XCTAssertEqual(core.state.importFlow, before)
    }

    private func begin(_ core: CrestCore, _ browser: BrowserStore) throws {
        try core.send(StartBrowserImport(workspaceID: browser.family.workspaceID))
        try core.send(OfferImportSources(installed: [.chrome]))
        try core.send(ToggleImportSource(source: .chrome))
        try core.send(ContinueImport())
    }

    private func project(_ flow: ImportFlowState, action: String, error: String?) -> [String: Any] {
        func optional<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func uuid(_ value: UUID?) -> Any { optional(value?.uuidString.lowercased()) }
        func ids(_ values: [UUID]) -> [String] { values.map { $0.uuidString.lowercased() } }
        let review = flow.review.map { review -> [String: Any] in
            [
                "source": review.source.name, "title": review.title, "spaceRoom": review.spaceRoom,
                "hasIncludedSpaces": review.hasIncludedSpaces, "includedTabCount": review.includedTabCount,
                "includedExtensionCount": review.includedExtensionCount, "nextSpaceId": uuid(review.nextSpaceID),
                "showsLastSpace": review.showsLastSpace, "newSpaceCapacity": review.newSpaceCapacity,
                "shownSpaceId": uuid(review.shownSpaceID), "overflowTabIds": ids(review.overflowTabIDs),
                "installs": review.extensionInstalls.map {
                    [
                        "extensionId": $0.extensionID, "name": $0.name, "iconPath": optional($0.iconPath),
                        "spaceIds": ids($0.spaceIDs),
                    ]
                },
                "spaces": review.spaces.map { space -> [String: Any] in
                    [
                        "id": uuid(space.source.id), "included": space.included,
                        "destinationId": uuid(space.destinationID), "name": space.customization.name,
                        "shownName": space.shownName, "includedTabIds": ids(space.includedTabIDs),
                        "duplicateTabIds": ids(space.duplicateTabIDs), "matchedTabIds": ids(space.matchedTabIDs),
                        "placements": space.placements.map {
                            ["tabId": uuid($0.tabID), "placement": $0.placement.name]
                        }, "extensions": space.extensions.map(\.extensionID),
                        "includedExtensionIds": space.includedExtensionIDs,
                        "brought": space.broughtExtensions.map(\.extensionID),
                    ]
                },
            ]
        }
        return [
            "action": action, "error": optional(error), "step": flow.step.name, "phase": flow.phase.rawValue,
            "offered": flow.offered.map(\.name), "selected": flow.selected.map(\.name),
            "source": optional(flow.source?.name),
            "queue": optional(
                flow.queue.map {
                    [
                        "sources": $0.sources.map(\.name), "index": $0.index, "current": optional($0.current?.name),
                        "hasMoreAfterCurrent": $0.hasMoreAfterCurrent,
                    ]
                }),
            "failure": optional(
                flow.failure.map {
                    ["reason": $0.reason.rawValue, "source": optional($0.source?.name), "detail": optional($0.detail)]
                }), "summary": optional(flow.summary.map { ["tabCount": $0.tabCount, "spaceCount": $0.spaceCount] }),
            "review": optional(review),
        ]
    }
}
