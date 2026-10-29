import Foundation
import XCTest

@testable import Crest

final class NativeSessionMutationTests: XCTestCase {
    private typealias Object = [String: Any]
    private func identifier(_ value: UUID?) -> Any { value?.uuidString.lowercased() ?? NSNull() as Any }
    private func seed(_ wire: String) throws -> SessionState.Seed {
        var reader = WireReader(Array(try XCTUnwrap(Data(base64Encoded: wire))))
        return try SessionState.Seed(from: &reader)
    }
    private func canonical(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    private func stamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 100_000).rounded() / 100_000)
    }
    private func stamped(_ source: SessionState.Seed) -> SessionState.Seed {
        func tab(_ value: TabState.Seed) -> TabState.Seed {
            var value = value
            value.lastActivatedAt = stamp(value.lastActivatedAt)
            value.positionModifiedAt = value.positionModifiedAt.map(stamp)
            value.titleModifiedAt = value.titleModifiedAt.map(stamp)
            return value
        }
        var value = source
        for index in value.spaces.indices {
            value.spaces[index].history = value.spaces[index].history.map { value in
                HistoryEntryState(
                    id: value.id, url: value.url, title: value.title, firstVisitedAt: stamp(value.firstVisitedAt),
                    lastVisitedAt: stamp(value.lastVisitedAt), visitCount: value.visitCount)
            }
            value.spaces[index].tabs = value.spaces[index].tabs.map(tab)
            value.spaces[index].folders = value.spaces[index].folders.map { source in
                var value = source
                value.collapseModifiedAt = value.collapseModifiedAt.map(stamp)
                return value
            }
            value.spaces[index].archivedTabs = value.spaces[index].archivedTabs.map { source in
                var value = source
                value.tab = tab(value.tab)
                value.archivedAt = stamp(value.archivedAt)
                return value
            }
        }
        return value
    }
    func testSessionRepairMatchesActualCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-mutations-crest-baseline.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
        let now = Date(timeIntervalSince1970: fixture["now"] as! Double)
        let rows = fixture["repairRows"] as! [Object]
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let label = row["label"] as! String
            var nextID = 1000
            var repair = SessionRepair(
                now: now,
                ids: {
                    defer { nextID += 1 }
                    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextID))!
                })
            do {
                let result = try repair.repair(seed(row["seed"] as! String))
                XCTAssertNil(row["failure"] as? String, label)
                guard let expected = row["repaired"] as? String else {
                    XCTFail("Unexpected repair: \(label)")
                    continue
                }
                XCTAssertEqual(stamped(result.session), stamped(try seed(expected)), label)
                let origins: [Object] = result.origins.map {
                    [
                        "spaceIndex": $0.spaceIndex, "tabIndex": $0.tabIndex, "space": identifier($0.sourceSpaceID),
                        "tab": identifier($0.sourceTabID),
                    ]
                }
                XCTAssertEqual(try canonical(origins), try canonical(row["origins"]!), label)
            } catch Rejection.invalidSession(let value) {
                XCTAssertTrue(
                    (row["failure"] as? String)?.lowercased().contains(String(describing: value.flaw).lowercased())
                        == true, label)
            } catch { XCTFail("\(label): \(error)") }
        }
    }
    func testTransfersBetweenRelatedWorkspacesMatchActualCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-transfers-crest-baseline.json")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Object])
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let label = row["mode"] as! String
            let source = row["source"] as! Object
            let destination = row["destination"] as! Object
            func scope(_ object: Object) throws -> SessionTransfer.Scope {
                let workspace = UUID(uuidString: object["workspace"] as! String)!
                var reader = WireReader(Array(Data(base64Encoded: object["window"] as! String)!))
                let state = try WindowState(from: &reader)
                let window = SessionWindow(
                    restoring: SessionWindow.Record(
                        id: state.id, shownSpaceID: state.shownSpaceID, tabs: state.shownTabs,
                        shares: state.splitColumnShares, used: 0), workspaceID: workspace)
                return SessionTransfer.Scope(
                    edits: SessionMutations(
                        workspaceID: workspace, kind: WorkspaceKind.named(object["kind"] as? String)!,
                        basis: try seed(object["before"] as! String), windows: [window.id: window],
                        now: Date(timeIntervalSince1970: row["now"] as! Double), ids: UUID.init),
                    borrowedFrom: (object["owner"] as? String).flatMap(UUID.init(uuidString:)),
                    isPrivate: object["isPrivate"] as! Bool)
            }
            var reader = WireReader(Array(Data(base64Encoded: row["request"] as! String)!))
            let request = try XCTUnwrap(CoreCodec.decodeIntent(from: &reader) as? MoveTabToWindow)
            var result: SessionTransfer?
            var failure: String?
            do { result = try SessionTransfer.between(request, from: scope(source), to: scope(destination)) } catch {
                failure = String(String(describing: error).split(separator: "(", maxSplits: 1)[0]).lowercased()
            }
            XCTAssertEqual(failure, (row["failure"] as? String)?.lowercased(), label)
            if let result {
                XCTAssertEqual(stamped(result.leaving.session), stamped(try seed(source["after"] as! String)), label)
                XCTAssertEqual(
                    stamped(result.arriving.session), stamped(try seed(destination["after"] as! String)), label)
            } else {
                XCTAssertNotNil(failure, label)
            }
        }
    }
    func testStoredDocumentsMatchActualCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-mutations-crest-baseline.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
        let rows = try XCTUnwrap(fixture["documentRows"] as? [Object])
        XCTAssertGreaterThan(rows.count, 20)
        for row in rows {
            let label = row["label"] as! String
            var decoded: SessionState.Seed?
            do { decoded = try SessionDocument.read(JSONSerialization.data(withJSONObject: row["input"]!)) } catch {
                XCTAssertEqual(row["failure"] as? Bool, true, "\(label): \(error)")
            }
            guard let decoded else { continue }
            XCTAssertEqual(row["failure"] as? Bool, false, label)
            if let wire = row["decoded"] as? String {
                XCTAssertEqual(stamped(decoded), stamped(try seed(wire)), label)
            } else {
                XCTFail("Unexpected document: \(label)")
                continue
            }
            XCTAssertEqual(try canonical(SessionDocument.encode(decoded)), try canonical(row["encoded"]!), label)
            let parts = try SessionDocument.checkpoint(decoded)
            XCTAssertEqual(try SessionDocument.restored(parts), decoded, label)
            if !decoded.spaces.isEmpty {
                var incomplete = parts
                incomplete.removeValue(forKey: "history." + decoded.spaces[0].id.uuidString)
                XCTAssertThrowsError(try SessionDocument.restored(incomplete), label)
            }
        }
    }
    func testCompleteEditsMatchActualCrest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/native-session-mutations-crest-baseline.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
        let workspaceID = try XCTUnwrap(UUID(uuidString: fixture["workspace"] as! String))
        let windowID = try XCTUnwrap(UUID(uuidString: fixture["window"] as! String))
        let now = Date(timeIntervalSince1970: fixture["now"] as! Double)
        let rows = fixture["rows"] as! [Object]
        XCTAssertGreaterThan(rows.count, 100)
        for (index, row) in rows.enumerated() {
            let label = "\(index): \(row["operation"]!)"
            let original = try seed(row["seed"] as! String)
            var window = SessionWindow(id: windowID, workspaceID: workspaceID, saved: false, session: original)
            window.showTab(original.spaces[0].tabs[4].id, in: original.spaces[0].id, moves: true)
            var windows = [windowID: window]
            if let spelling = fixture["secondWindow"] as? String, let id = UUID(uuidString: spelling) {
                var second = SessionWindow(id: id, workspaceID: workspaceID, saved: false, session: original)
                second.showTab(original.spaces[0].tabs[7].id, in: original.spaces[0].id, moves: true)
                windows[id] = second
            }
            var nextID = 1000
            let mutations = SessionMutations(
                workspaceID: workspaceID, kind: .persistent, basis: original, windows: windows, now: now,
                ids: {
                    defer { nextID += 1 }
                    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextID))!
                })
            var reader = WireReader(Array(try XCTUnwrap(Data(base64Encoded: row["request"] as! String))))
            let request = try CoreCodec.decodeIntent(from: &reader)
            var result: SessionMutation?
            var failure: String?
            do {
                if let intent = request as? any SessionIntent {
                    result = try mutations.apply(intent)
                } else {
                    result = try mutations.pageRecord(request)
                }
            } catch {
                failure = String(String(describing: error).split(separator: "(", maxSplits: 1)[0]).lowercased()
            }
            XCTAssertEqual(failure, (row["failure"] as? String)?.lowercased(), label)
            guard let expected = row["result"] as? Object else {
                XCTAssertNil(result, label)
                continue
            }
            guard let result else {
                XCTFail("Missing edit: \(label)")
                continue
            }
            let targetSeed = try seed(expected["session"] as! String)
            var actualSeed = result.session
            if request is RefreshLiveFolder {
                let retained = Set(original.spaces.flatMap { $0.tabs.map(\.id) + $0.archivedTabs.map(\.tab.id) })
                XCTAssertEqual(
                    Set(actualSeed.spaces.flatMap { $0.tabs.map(\.id) }).count,
                    actualSeed.spaces.reduce(0) { $0 + $1.tabs.count }, label)
                for si in targetSeed.spaces.indices {
                    for ti in targetSeed.spaces[si].tabs.indices
                    where !retained.contains(targetSeed.spaces[si].tabs[ti].id) {
                        guard actualSeed.spaces[si].tabs.indices.contains(ti) else { continue }
                        XCTAssertFalse(retained.contains(actualSeed.spaces[si].tabs[ti].id), label)
                        XCTAssertNotEqual(actualSeed.spaces[si].tabs[ti].id, SessionValidation.emptyID, label)
                        actualSeed.spaces[si].tabs[ti].id = targetSeed.spaces[si].tabs[ti].id
                    }
                }
            }
            XCTAssertEqual(stamped(actualSeed), stamped(targetSeed), label)
            let reason: String?
            if let stage = result.stage {
                reason =
                    [.launch, .expiry].contains(stage)
                    ? "retention"
                    : [.batchDeletion, .deletion, .removal].contains(stage) ? "explicitDelete" : "superseded"
            } else {
                reason = nil
            }
            XCTAssertEqual(reason, expected["reason"] as? String, label)
            let delay: Double? = result.stage.map { [.tabUse, .pageReport].contains($0) ? 30 : $0 == .edit ? 0.15 : 0 }
            let saves = result.stage.map {
                [.transfer, .batch, .batchDeletion, .withdrawal, .removal, .importing].contains($0)
            }
            XCTAssertEqual(delay, expected["delay"] as? Double, label)
            XCTAssertEqual(saves, expected["saves"] as? Bool, label)
            if let follow = result.followUp, let target = expected["follow"] as? Object {
                let actual: Object = [
                    "space": identifier(follow.spaceID),
                    "tabs": follow.tabs.sorted { $0.spaceID.uuidString < $1.spaceID.uuidString }.map {
                        ["space": identifier($0.spaceID), "tab": identifier($0.tabID)]
                    },
                    "dismissed": follow.dismissed.map { ["space": identifier($0.space), "tab": identifier($0.tab)] },
                    "departed": follow.departed.map {
                        ["window": identifier($0.window), "space": identifier($0.space), "tab": identifier($0.tab)]
                    },
                ]
                XCTAssertEqual(try canonical(actual), try canonical(target), label)
            } else {
                XCTAssertEqual(result.followUp == nil, expected["follow"] is NSNull, label)
            }
            let imported = result.effects.compactMap { $0 as? TabsImported }.flatMap(\.tabs).map {
                ["TabId": identifier($0.tabID), "Source": $0.source, "SourceTabId": identifier($0.sourceTabID)]
                    as Object
            }
            XCTAssertEqual(try canonical(imported), try canonical(expected["imported"] as? [Any] ?? []), label)
            if let icon = result.effects.compactMap({ $0 as? TabFaviconAssigned }).first,
                let target = expected["favicon"] as? Object
            {
                XCTAssertEqual(
                    try canonical([
                        "tab": identifier(icon.tabID), "adopts": icon.adopts, "page": identifier(icon.pageID),
                    ]), try canonical(target), label)
            } else {
                XCTAssertEqual(
                    result.effects.contains { $0 is TabFaviconAssigned }, expected["favicon"] is Object, label)
            }
            let copied = result.effects.compactMap { $0 as? TabCopied }.map {
                ["source": identifier($0.sourceTabID), "copy": identifier($0.copyTabID)]
            }
            XCTAssertEqual(try canonical(copied), try canonical(expected["copied"] as? [Any] ?? []), label)
            if let away = result.effects.compactMap({ $0 as? TabPagePutAway }).first,
                let target = expected["putAway"] as? Object
            {
                XCTAssertEqual(
                    try canonical([
                        "space": identifier(away.spaceID), "tab": identifier(away.tabID),
                        "window": identifier(away.windowID), "keepsState": away.keepsState,
                    ]), try canonical(target), label)
            } else {
                XCTAssertEqual(result.effects.contains { $0 is TabPagePutAway }, expected["putAway"] is Object, label)
            }
        }
    }
}
