import Foundation
import XCTest

@testable import Crest

final class NativePageHistoryTests: XCTestCase {
    private struct Entry: Decodable {
        let id: UUID
        let url: String
        let title: String
        var value: PageHistoryEntry { PageHistoryEntry(id: id, url: url, title: title) }
    }
    private struct Action: Decodable {
        let kind: String
        let entries: [Entry]?
        let current: Int?
        let restores: Bool?
        let id: UUID?
    }
    private struct Answer: Decodable {
        let entries: [Entry]
        let current: Int
        let back: [UUID]
        let forward: [UUID]
        let target: UUID?
    }
    private struct Trace: Decodable {
        let actions: [Action]
        let answers: [Answer]
    }
    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
                "Fixtures/" + name))
    }
    func testTransitionsAndArchivesMatchTheActualCrestHistory() throws {
        let data = try fixture("page-history-crest-baseline.json")
        let traces = try JSONDecoder().decode([Trace].self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(traces.count, 36)
        var checked = 0
        for (traceIndex, trace) in traces.enumerated() {
            var history = NativePageHistory()
            let answers = try XCTUnwrap(raw[traceIndex]["answers"] as? [[String: Any]])
            for (index, action) in trace.actions.enumerated() {
                let expected = trace.answers[index]
                var target: UUID?
                switch action.kind {
                case "report":
                    target = history.report(try XCTUnwrap(action.entries).map(\.value), try XCTUnwrap(action.current))
                case "reopen": history.reopen(restores: try XCTUnwrap(action.restores))
                case "go": history.go(try XCTUnwrap(action.id))
                case "load": history.load(try XCTUnwrap(action.id))
                case "archive": history = try XCTUnwrap(NativePageHistory.unarchive(history.archive()))
                default: return XCTFail("Unknown fixture action")
                }
                let message = "Trace \(traceIndex), step \(index), \(action.kind)"
                XCTAssertEqual(history.entries, expected.entries.map(\.value), message)
                XCTAssertEqual(history.current, expected.current, message)
                XCTAssertEqual(history.back.map(\.id), expected.back, message)
                XCTAssertEqual(history.forward.map(\.id), expected.forward, message)
                XCTAssertEqual(target, expected.target, message)
                if let expectedArchive = answers[index]["archive"] as? [String: Any] {
                    let archive = try XCTUnwrap(history.archive(), message)
                    let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
                    XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: expectedArchive), message)
                } else {
                    XCTAssertNil(history.archive(), message)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 612)
    }
    func testPageIdentityMatchesCrestIncludingUnicodeAndNonWebFragments() throws {
        struct Row: Decodable {
            let first: String
            let second: String
            let same: Bool
        }
        let rows = try JSONDecoder().decode([Row].self, from: fixture("page-address-crest-baseline.json"))
        XCTAssertEqual(rows.count, 88)
        for row in rows {
            XCTAssertEqual(PageAddress.samePage(row.first, row.second), row.same, "\(row.first) vs \(row.second)")
        }
    }
    func testInvalidNativeReportsAndArchivesDoNotReplaceUsableHistory() throws {
        let entries = (0..<3).map {
            PageHistoryEntry(id: UUID(), url: "https://history.example/\($0)", title: "Page \($0)")
        }
        let history = NativePageHistory()
        history.report(entries, 1)
        XCTAssertFalse(NativePageHistory.holds(entries, -1))
        XCTAssertFalse(NativePageHistory.holds(entries, 3))
        XCTAssertTrue(NativePageHistory.holds([], -1))
        history.report([entries[0], entries[0]], 1)
        XCTAssertEqual(history.entries, entries)
        XCTAssertNil(NativePageHistory.unarchive(history.archive()?.prefix(10)))
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(history.archive())) as? [String: Any])
        var runs = try XCTUnwrap(stored["runs"] as? [[String: Any]])
        var invalid = try XCTUnwrap(runs[0]["entries"] as? [[String: Any]])
        invalid[1]["id"] = invalid[0]["id"]
        runs[0]["entries"] = invalid
        stored["runs"] = runs
        XCTAssertNil(NativePageHistory.unarchive(try JSONSerialization.data(withJSONObject: stored)))
    }
    func testColdHistoryTrimsOldEntriesAtWebKitCapacityAndNewNavigationDropsForwardHistory() {
        let history = NativePageHistory()
        let entries = (0..<100).map {
            PageHistoryEntry(id: UUID(), url: "https://old.example/\($0)", title: "Old \($0)")
        }
        history.report(entries, 99)
        history.reopen(restores: false)
        history.report([PageHistoryEntry(id: UUID(), url: entries[99].url, title: "Fresh")], 0)
        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.back.count, 99)
        let newer = (0..<100).map { PageHistoryEntry(id: UUID(), url: "https://new.example/\($0)", title: "New \($0)") }
        history.report(newer, 99)
        XCTAssertEqual(history.entries, newer)
        XCTAssertEqual(history.back.count, 99)
        history.report(newer, 1)
        let branch = PageHistoryEntry(id: UUID(), url: "https://branch.example/", title: "Branch")
        history.report([newer[0], newer[1], branch], 2)
        XCTAssertTrue(history.forward.isEmpty)
        XCTAssertFalse(history.reaches(newer[2].id))
    }
}
