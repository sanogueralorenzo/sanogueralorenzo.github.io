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
            var nextID = 1000
            let mutations = SessionMutations(
                workspaceID: workspaceID, kind: .persistent, basis: original, windows: [windowID: window], now: now,
                ids: {
                    defer { nextID += 1 }
                    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextID))!
                })
            var reader = WireReader(Array(try XCTUnwrap(Data(base64Encoded: row["request"] as! String))))
            let request = try XCTUnwrap(CoreCodec.decodeIntent(from: &reader) as? any SessionIntent)
            var result: SessionMutation?
            var failure: String?
            do { result = try mutations.apply(request) } catch {
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
            XCTAssertEqual(stamped(result.session), stamped(try seed(expected["session"] as! String)), label)
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
                ]
                XCTAssertEqual(try canonical(actual), try canonical(target), label)
            } else {
                XCTAssertEqual(result.followUp == nil, expected["follow"] is NSNull, label)
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
