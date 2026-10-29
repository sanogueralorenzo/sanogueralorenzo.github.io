import Foundation
import Observation
import XCTest

@testable import Crest

@MainActor
final class NativeShortcutTests: XCTestCase {
    private func baseline() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/shortcuts-crest-baseline.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// Captured from Crest before removing its C# catalog. All stable metadata,
    /// platform defaults, menus and special keys retain their exact order.
    func testNativeCatalogMatchesCrest() throws {
        let expected = try baseline()
        func optional<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let commands: [[String: Any]] = ShortcutCommand.all.map { command in
            [
                "name": command.name, "kind": String(describing: command.kind), "section": command.section.name,
                "symbol": command.symbol, "capability": optional(command.requiredCapability?.name),
                "target": optional(command.selects?.name),
                "number": optional(command.number), "paletteRest": optional(command.paletteRest),
                "offersInPalette": command.offersInPalette,
                "isReservedFromPages": command.isReservedFromPages,
                "defaults": command.defaultShortcuts.map {
                    [
                        "platform": $0.platform.name, "key": $0.keys.key, "isSpecialKey": $0.keys.isSpecialKey,
                        "modifiers": Int($0.keys.modifiers.rawValue),
                    ] as [String: Any]
                },
            ]
        }
        let menus: [[String: Any]] = ShortcutMenu.all.map {
            ["name": $0.name, "groups": $0.groups.map { $0.map(\.name) }]
        }
        let keys: [[String: Any]] = ShortcutSpecialKey.all.map {
            ["name": $0.name, "glyph": optional($0.glyph), "functionKeyNumber": optional($0.functionKeyNumber)]
        }
        XCTAssertEqual(commands as NSArray, try XCTUnwrap(expected["commands"] as? NSArray))
        XCTAssertEqual(menus as NSArray, try XCTUnwrap(expected["menus"] as? NSArray))
        XCTAssertEqual(keys as NSArray, try XCTUnwrap(expected["keys"] as? NSArray))
        XCTAssertEqual(Set(ShortcutCommand.all.map(\.name)).count, ShortcutCommand.all.count)
        for platform in DevicePlatform.all {
            let defaults = ShortcutCommand.all.compactMap {
                $0.defaultShortcuts.first { $0.platform == platform }.map { BrowserShortcut($0.keys) }
            }
            XCTAssertTrue(defaults.allSatisfy(\.isValid))
            XCTAssertEqual(Set(defaults).count, defaults.count)
        }
    }

    func testAvailabilityMatchesEveryCrestTruthTableCase() throws {
        let cases = try XCTUnwrap(baseline()["availability"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 576)
        for row in cases {
            let surface = TabSurface.named(try XCTUnwrap(row["surface"] as? String))
            let placement = try XCTUnwrap(TabPlacement.named(row["placement"] as? String))
            let showsSpace = try XCTUnwrap(row["showsSpace"] as? Bool)
            let isPrivate = try XCTUnwrap(row["isPrivate"] as? Bool)
            let archived = try XCTUnwrap(row["archived"] as? Bool)
            let candidate = try XCTUnwrap(row["candidate"] as? Bool)
            let cards = try XCTUnwrap(row["cards"] as? Int)
            let unavailable = ShortcutCommand.all.filter {
                !$0.availability.allows(
                    showsSpace: showsSpace, isPrivate: isPrivate, surface: surface, placement: placement,
                    archived: archived, candidate: candidate, cards: cards)
            }.map(\.name)
            XCTAssertEqual(unavailable, try XCTUnwrap(row["unavailable"] as? [String]), "\(row)")
        }
    }

    func testFixedBindingsFollowCapabilitiesWithoutASecondStoredCatalog() {
        let core = CrestCore()
        let store = BrowserShortcutStore(core: core)
        XCTAssertTrue(store.offeredCommands.contains(.toggleReaderMode))
        core.state.engines = EngineRoster(offered: EngineCapability.all.filter(\.isRequired))
        XCTAssertFalse(store.offeredCommands.contains(.toggleReaderMode))
        XCTAssertFalse(store.offeredCommands.contains(.translatePage))
        XCTAssertFalse(store.offeredCommands.contains(.toggleContentBlocking))
        XCTAssertEqual(store.shortcut(for: .newTab), .init(key: .character("t"), modifiers: .command))
        core.state.engines = EngineRoster(offered: EngineCapability.all)
        XCTAssertTrue(store.offeredCommands.contains(.toggleReaderMode))
    }

    func testNumberedStopsRespectNestedCollapseSplitsAndUnavailableSpaces() throws {
        let core = CrestCore()
        let space = UUID()
        let parent = UUID()
        let child = UUID()
        let split = UUID()
        let pinned = UUID()
        let saved = UUID()
        let nested = UUID()
        let first = UUID()
        let second = UUID()
        let last = UUID()
        func tab(_ id: UUID, _ placement: TabPlacement, folder: UUID? = nil, group: UUID? = nil) -> TabState.Seed {
            TabState.Seed(
                id: id, title: "Tab", url: URL(string: "https://example.org/\(id)"), placement: placement,
                folderID: folder, splitGroupID: group)
        }
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(
                    id: space, name: "Work",
                    folders: [
                        FolderState.Seed(id: parent, title: "Parent"),
                        FolderState.Seed(id: child, title: "Child", parentID: parent, isCollapsed: true),
                    ],
                    tabs: [
                        tab(pinned, .pinned), tab(saved, .saved, folder: parent), tab(nested, .saved, folder: child),
                        tab(first, .current, group: split), tab(second, .current, group: split), tab(last, .current),
                        .startPage(),
                    ]),
                SpaceState.Seed(name: "Other", tabs: []),
            ]), core: core)
        func selectedTabs() -> [UUID] {
            let choices = core.numberedSelections(windowID: browser.windowID)
            return (1...9).compactMap { number in
                ShortcutCommand.selecting(.tab, number: number).flatMap { choices[$0]?.tabID }
            }
        }
        XCTAssertEqual(selectedTabs(), [pinned, saved, first, last])
        try core.send(
            CollapseFolder(workspaceID: browser.family.workspaceID, spaceID: space, folderID: child, collapsed: false)
        )
        XCTAssertEqual(selectedTabs(), [pinned, saved, nested, first, last])
        try core.send(
            CollapseFolder(workspaceID: browser.family.workspaceID, spaceID: space, folderID: parent, collapsed: true)
        )
        XCTAssertEqual(selectedTabs(), [pinned, first, last])
        XCTAssertTrue(core.numberedSelections(windowID: UUID()).isEmpty)
        let other = try XCTUnwrap(browser.spaceModels.last)
        try XCTUnwrap(browser.workspaceModel).apply(
            WorkspaceChanged(
                workspaceID: browser.family.workspaceID, isDisposableSeed: false,
                spaceDeletions: [SpaceDeletionState(id: UUID(), spaceID: other.id, profileID: other.profileID)]))
        XCTAssertNil(core.numberedSelections(windowID: browser.windowID)[.selectSpace2])
    }

    func testWindowAvailabilityReadsRelevantSlotsAndTracksSelection() throws {
        let id = UUID()
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(
                    name: "Work",
                    tabs: [
                        TabState.Seed(
                            id: id, title: "Page", url: URL(string: "https://example.org"), placement: .current)
                    ])
            ]))
        XCTAssertTrue(browser.allows(.reloadPage))
        XCTAssertTrue(browser.allows(.archiveTab))
        var invalidated = false
        withObservationTracking {
            XCTAssertTrue(browser.allows(.reloadPage))
        } onChange: {
            MainActor.assumeIsolated { invalidated = true }
        }
        browser.setTabCustomTitle("Renamed", for: id, in: browser.selectedSpaceID)
        XCTAssertFalse(invalidated, "Renaming a tab must not invalidate its reload availability")
        _ = browser.openNewTab()
        XCTAssertFalse(browser.allows(.reloadPage))
        XCTAssertFalse(browser.allows(.archiveTab))
    }

    func testNativeKeyNamesRoundTripAndCanonicallyEquivalentCharactersMatch() throws {
        let first = BrowserShortcut(key: .character("é"), modifiers: .command)
        let decomposed = try XCTUnwrap(
            BrowserShortcut(boundKeys: KeyCombination(key: "e\u{0301}", isSpecialKey: false, modifiers: .command)))
        XCTAssertEqual(first, decomposed)
        XCTAssertNil(BrowserShortcut(boundKeys: KeyCombination(key: "", isSpecialKey: false, modifiers: .command)))
        XCTAssertNil(BrowserShortcut(boundKeys: KeyCombination(key: "hyper", isSpecialKey: true, modifiers: .command)))
        let special = BrowserShortcut(key: .special(.f20), modifiers: [.control, .option])
        XCTAssertEqual(try JSONDecoder().decode(BrowserShortcut.self, from: JSONEncoder().encode(special)), special)
    }
}
