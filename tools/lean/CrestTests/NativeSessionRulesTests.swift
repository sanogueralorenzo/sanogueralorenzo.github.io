import Foundation
import XCTest

@testable import Crest

final class NativeSessionRulesTests: XCTestCase {
    private typealias Object = [String: Any]
    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
    private func identifier(_ value: UUID?) -> Any { value?.uuidString.lowercased() ?? NSNull() as Any }
    private func time(_ value: Date?) -> Any {
        value.map { ($0.timeIntervalSince1970 * 100_000).rounded() / 100_000 } ?? NSNull() as Any
    }
    private func base() throws -> SessionTabs {
        let folders = [
            FolderState.Seed(id: id(10), title: "Saved"),
            FolderState.Seed(id: id(12), title: "Nested", parentID: id(10)),
            FolderState.Seed(id: id(11), title: "Current", location: .current),
            FolderState.Seed(id: id(13), title: "Empty", location: .current, orderAnchorTabID: id(8)),
        ]
        let tabs = (1...8).map { n in
            TabState.Seed(
                id: id(n), title: "Tab \(n)", url: URL(string: "https://example.com/\(n)"),
                placement: n <= 2 ? .pinned : n <= 4 ? .saved : .current,
                folderID: n == 3 || n == 4 ? id(10) : n == 6 || n == 7 ? id(11) : nil,
                splitGroupID: n == 3 || n == 4 ? id(91) : n == 6 || n == 7 ? id(90) : nil,
                lastActivatedAt: Date(timeIntervalSince1970: Double(n)))
        }
        return try SessionTabs(tabs: tabs, folders: folders)
    }
    private func snapshot(_ values: SessionTabs) -> Object {
        [
            "tabs": values.tabs.map { value -> Object in
                [
                    "id": identifier(value.id), "title": value.title, "url": value.url ?? NSNull() as Any,
                    "saved": value.savedURL ?? NSNull() as Any, "symbol": value.symbol,
                    "folder": identifier(value.folderID), "split": identifier(value.splitGroupID),
                    "placement": value.placement.name, "activated": time(value.lastActivatedAt),
                    "position": time(value.positionModifiedAt), "custom": value.customTitle ?? NSNull() as Any,
                    "renamed": time(value.titleModifiedAt),
                ]
            },
            "folders": values.folders.map { value -> Object in
                [
                    "id": identifier(value.id), "title": value.title, "placement": value.location.name,
                    "parent": identifier(value.parentID), "anchor": identifier(value.orderAnchorTabID),
                    "collapsed": value.isCollapsed, "collapse": time(value.collapseModifiedAt),
                    "color": value.color.map { [$0.red, $0.green, $0.blue, $0.alpha] } ?? NSNull() as Any,
                ]
            },
            "archive": values.archived.map { value -> Object in
                [
                    "id": identifier(value.tab.id), "placement": value.tab.placement.name,
                    "folder": identifier(value.tab.folderID), "split": identifier(value.tab.splitGroupID),
                    "saved": value.tab.savedURL ?? NSNull() as Any, "reason": value.reason.name,
                    "at": time(value.archivedAt),
                ]
            },
        ]
    }
    private func canonical(_ value: Any) throws -> Data {
        func rounded(_ value: Any, key: String? = nil) -> Any {
            if let values = value as? [Any] { return values.map { rounded($0) } }
            if let values = value as? Object {
                return values.reduce(into: Object()) { $0[$1.key] = rounded($1.value, key: $1.key) }
            }
            if ["activated", "position", "renamed", "collapse", "at"].contains(key ?? ""), let number = value as? Double
            {
                return (number * 100_000).rounded() / 100_000
            }
            return value
        }
        return try JSONSerialization.data(withJSONObject: rounded(value), options: [.sortedKeys, .fragmentsAllowed])
    }
    @MainActor
    func testNativePresentationMatchesTheFullSessionPublishedByCrest() throws {
        let core = try CrestCore(
            configuration: AppConfiguration(storageDirectory: nil, platform: .desktop, importNames: nil))
        let values = try base()
        var tabs = values.tabs
        tabs[0].symbol = "crest.emoji:📚"
        tabs[0].customTitle = "  Books  "
        tabs[1].faviconURL = tabs[1].url! + "#icon"
        tabs[1].url = "https://elsewhere.example.com/"
        var native = TabState.Seed.startPage(id: id(40))
        native.nativeContent = NativeTabContent(kind: "settings", resourceID: nil)
        native.title = "Settings"
        tabs.append(native)
        native.id = id(41)
        native.nativeContent = NativeTabContent(kind: "future-view", resourceID: id(99))
        tabs.append(native)
        tabs.append(.startPage(id: id(42)))
        let seed = SessionState.Seed(spaces: [
            SpaceState.Seed(id: id(20), profileID: id(21), name: "Work", folders: values.folders, tabs: tabs)
        ])
        let changes = try core.send(OpenWorkspace(kind: .persistent, seed: seed))
        let opened = try XCTUnwrap(
            changes.compactMap { change -> WorkspaceOpened? in
                if case .workspaceOpened(let value) = change { return value }
                return nil
            }.first)
        defer { _ = try? core.send(CloseWorkspace(workspaceID: opened.workspaceID)) }
        XCTAssertEqual(opened.session.seed.resolved, opened.session)
    }
    private func windowSnapshot(_ window: SessionWindow, over session: SessionState.Seed) -> Object {
        let state = window.state(over: session)
        return [
            "id": identifier(state.id), "workspace": identifier(state.workspaceID),
            "shown": identifier(state.shownSpaceID),
            "tabs": state.shownTabs.map { ["space": identifier($0.spaceID), "tab": identifier($0.tabID)] },
            "shares": state.splitColumnShares.map { ["group": identifier($0.groupID), "values": $0.shares] as Object },
            "cards": state.cards.map {
                [
                    "space": identifier($0.spaceID), "tabs": $0.tabIDs.map(identifier),
                    "group": identifier($0.splitGroupID),
                ]
            },
            "recent": session.spaces.map { space in
                [
                    "space": identifier(space.id),
                    "items": window.recentItems(in: space).map {
                        ["tabs": $0.tabIDs.map(identifier), "focus": identifier($0.focusedTabID)]
                    },
                ] as Object
            },
            "last": session.spaces.map {
                ["space": identifier($0.id), "tab": identifier(window.lastUsed(in: $0, elsewhere: [])?.focusedTabID)]
            },
            "onScreen": window.onScreen(in: session).map(identifier),
        ]
    }
    func testWindowHistoryNullSelectionRepairAndSidebarNavigationMatchCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-window-crest-baseline.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
        let values = try base()
        let work = SpaceState.Seed(
            id: id(20), profileID: id(21), name: "Work", folders: values.folders, tabs: values.tabs)
        var otherTab = values.tabs[4]
        otherTab.id = id(105)
        let other = SpaceState.Seed(id: id(30), profileID: id(31), name: "Other", tabs: [otherTab])
        var session = SessionState.Seed(spaces: [work, other])
        var window = SessionWindow(id: id(500), workspaceID: id(600), saved: true, session: session)
        for (index, row) in (root["rows"] as! [Object]).enumerated() {
            let action = row["action"] as! String
            let space = id(row["space"] as! Int)
            let tab = (row["tab"] as? Int).map(id)
            var answer: Any = NSNull()
            switch action {
            case "show": window.showTab(tab, in: space, moves: true)
            case "space": window.showSpace(session.spaces.first { $0.id == space }!)
            case "adopt": window.adopt(tab, in: space)
            case "depart": window.depart(tab!, in: space)
            case "move": window.move(to: space)
            case "forget": window.forgetTabs()
            case "resize": answer = window.resize(id(90), shares: row["shares"] as! [Double])
            case "fallback":
                answer = identifier(
                    window.dismissalFallback(
                        in: space, dismissing: tab!,
                        available: Set(session.spaces.first { $0.id == space }!.tabs.map(\.id))))
            case "repair": window.repair(over: session)
            case "removeTab":
                session.spaces[session.spaces.firstIndex { $0.id == space }!].tabs = work.tabs.filter { $0.id != tab }
                window.repair(over: session)
            case "deleting":
                session.spaceDeletions = [SpaceDeletionState(id: id(800), spaceID: space, profileID: id(21))]
                window.repair(over: session)
            case "removeSpace":
                session.spaces.removeAll { $0.id == space }
                session.spaceDeletions = []
                window.repair(over: session)
            case "copy": window = SessionWindow(copying: window, id: id(501), saved: true)
            case "restore": window = SessionWindow(restoring: window.record(used: 8), workspaceID: id(600))
            case "empty":
                session.spaces = []
                session.spaceDeletions = []
                window.repair(over: session)
            case "launchEmpty": window = SessionWindow(id: id(502), workspaceID: id(600), saved: true, session: session)
            case "initial": break
            default: return XCTFail("Unknown window fixture action \(action)")
            }
            XCTAssertEqual(try canonical(answer), try canonical(row["answer"]!), "\(index) \(action) answer")
            XCTAssertEqual(
                String(decoding: try canonical(windowSnapshot(window, over: session)), as: UTF8.self),
                String(decoding: try canonical(row["state"]!), as: UTF8.self), "\(index) \(action) state")
        }
        let sidebar = SessionSidebar(tabs: values.tabs, folders: values.folders)
        let actual = sidebar.outline.lists.map { list in
            [
                "section": list.section.name, "folder": identifier(list.folderID),
                "rows": list.rows.map {
                    [
                        "id": identifier($0.id), "kind": $0.kind.name, "parent": identifier($0.parentFolderID),
                        "depth": $0.depth, "members": $0.members.map(identifier),
                    ] as Object
                },
            ] as Object
        }
        XCTAssertEqual(try canonical(actual), try canonical(root["sidebar"]!))
        for row in root["stepping"] as! [Object] {
            let tab = UUID(uuidString: row["tab"] as! String)!
            for direction in AdjacentDirection.all {
                let key = direction == .previous ? "previous" : "next"
                let swipeKey = direction == .previous ? "swipePrevious" : "swipeNext"
                XCTAssertEqual(
                    try canonical(identifier(sidebar.step(tab, direction: direction, folders: values.folders))),
                    try canonical(row[key]!))
                XCTAssertEqual(
                    try canonical(identifier(sidebar.swipe(tab, direction: direction, folders: values.folders))),
                    try canonical(row[swipeKey]!))
            }
        }
    }
    func testTabFolderAndSplitEditsMatchActualCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-rules-crest-baseline.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
        let now = Date(timeIntervalSince1970: root["now"] as! Double)
        let rows = root["rows"] as! [Object]
        XCTAssertGreaterThan(rows.count, 200)
        for (step, row) in rows.enumerated() {
            var values = try base()
            var counter = 1000
            func next() -> UUID {
                defer { counter += 1 }
                return id(counter)
            }
            func optionalID(_ key: String) -> UUID? { (row[key] as? Int).map(id) }
            let action = row["action"] as! String
            let tab = id(row["tab"] as! Int)
            let target = id(row["target"] as! Int)
            let index = row["index"] as? Int
            let placement = TabPlacement.named(row["placement"] as? String)
            let folder = optionalID("folder")
            let before = optionalID("before")
            let detach = row["detach"] as! Bool
            var answer: Any = NSNull()
            var failure: String?
            do {
                let selection =
                    action.hasSuffix("Selected")
                    ? try values.select(
                        TabSelection(tabIDs: [tab, target], folderIDs: [], memberTabIDs: [tab, target])) : nil
                switch action {
                case "closeSelected":
                    answer = identifier(try values.close(selection!, shown: tab, fallback: id(8), at: now))
                case "deleteSelected":
                    answer = identifier(try values.delete(selection!, shown: tab, fallback: id(8), at: now))
                case "duplicateSelected":
                    answer = try values.duplicate(selection!, ids: next, at: now).map {
                        ["source": identifier($0.source), "copy": identifier($0.copy)]
                    }
                case "splitSelected":
                    let joined = try values.split(selection!, target: nil, index: index, shown: tab, ids: next, at: now)
                    answer = [
                        "selected": identifier(joined.shown),
                        "copies": joined.copies.map { ["source": identifier($0.source), "copy": identifier($0.copy)] },
                    ]
                case "separateSelected": try values.separate(selection!, at: now)
                case "fileSelected":
                    try values.file(
                        selection!, at: placement!, folder: folder, before: nil, beforeFolder: nil,
                        leavesSplits: detach, now: now)
                case "folderSelected":
                    answer = identifier(
                        try values.folder(
                            selection!, placement: .current, title: "Group",
                            color: BrandColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), ids: next, now: now))
                case "move":
                    answer = try values.move(
                        tab, to: placement!, folder: folder, before: before, detachSplit: detach, at: now)
                case "join":
                    let joined = try values.join(tab, to: target, index: index, ids: next, at: now)
                    answer = [
                        "selected": identifier(joined.selected),
                        "copies": joined.copies.map { ["source": identifier($0.source), "copy": identifier($0.copy)] },
                    ]
                case "duplicate":
                    answer = identifier(
                        try values.duplicate(tab, ids: next, at: now, placement: placement ?? .current, index: index).id
                    )
                case "leave": try values.leaveSplit(tab, at: now)
                case "step": answer = try values.stepSplitMember(tab, offset: index ?? 0, at: now)
                case "dissolve": answer = values.dissolveSplit(target, at: now)
                case "dismiss":
                    answer = identifier(
                        try values.dismiss(
                            [tab], selected: tab, fallback: target, at: now, deleting: row["deleting"] as! Bool,
                            ensuresSelection: row["ensure"] as! Bool, resetsPlacement: row["reset"] as! Bool))
                case "rename": try values.rename(tab, title: row["name"] as? String, at: now)
                case "addFolder":
                    try values.addFolder(
                        tab, name: row["name"] as? String ?? "New", location: placement ?? .saved, parent: folder)
                case "renameFolder": try values.renameFolder(tab, name: row["name"] as? String ?? "")
                case "collapseFolder": try values.collapseFolder(tab, collapsed: detach, at: now)
                case "colorFolder":
                    answer = try values.colorFolder(tab, color: BrandColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
                case "deleteFolder": answer = try values.deleteFolder(tab, at: now).map { identifier($0.id) }
                case "moveFolder":
                    try values.moveFolder(
                        tab, location: placement, parent: folder, at: now, beforeFolder: before,
                        beforeTab: (row["target"] as! Int) == 0 ? nil : target)
                case "file":
                    try values.file(
                        [tab], at: placement!, folder: folder, now: now, before: before,
                        beforeFolder: (row["target"] as! Int) == 0 ? nil : target, detachesSplitMembers: detach)
                default: return XCTFail("Unknown fixture action \(action)")
                }
            } catch let error as Rejection {
                let name = Mirror(reflecting: error).children.first!.label!
                failure = name.prefix(1).uppercased() + name.dropFirst()
            } catch is SessionFolders.InvalidTree { failure = "InvalidTree" }
            let context = "Step \(step): \(action)"
            XCTAssertEqual(failure, row["failure"] as? String, context)
            XCTAssertEqual(try canonical(answer), try canonical(row["answer"]!), context + " answer")
            XCTAssertEqual(try canonical(snapshot(values)), try canonical(row["state"]!), context + " state")
        }
    }
}
