import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserFileUploadAccessTests: XCTestCase {
    func testSelectionStartsAccessBeforeReadingAndRetainsItUntilPageCleanup() throws {
        let url = URL(fileURLWithPath: "/selected/report.txt")
        var events: [String] = []
        let access = BrowserFileUploadAccess(
            start: { _ in
                events.append("start")
                return true
            },
            stop: { _ in events.append("stop") },
            validate: { _ in events.append("read") }
        )
        try access.prepare([url])
        XCTAssertEqual(events, ["start", "read"])
        try access.prepare([url])
        XCTAssertEqual(events, ["start", "read", "read"])
        access.invalidate()
        access.invalidate()
        XCTAssertEqual(events, ["start", "read", "read", "stop"])
    }

    func testFailedSelectionReleasesNewGrantsButPreservesEarlierSelections() throws {
        let first = URL(fileURLWithPath: "/selected/first.txt")
        let second = URL(fileURLWithPath: "/selected/second.txt")
        let denied = URL(fileURLWithPath: "/selected/denied.txt")
        var stopped: [URL] = []
        let access = BrowserFileUploadAccess(
            start: { _ in true },
            stop: { stopped.append($0) },
            validate: {
                if $0 == denied { throw CocoaError(.fileReadNoPermission) }
            }
        )
        try access.prepare([first])
        XCTAssertThrowsError(try access.prepare([second, denied]))
        XCTAssertEqual(Set(stopped), Set([second, denied]))
        access.invalidate()
        XCTAssertEqual(Set(stopped), Set([first, second, denied]))
    }

    func testUnscopedLocalFilesAreValidatedWithoutRequiringASandboxGrant() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("upload".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let access = BrowserFileUploadAccess()
        try access.prepare([root])
        XCTAssertThrowsError(try access.prepare([root.appendingPathExtension("missing")]))
        access.invalidate()
    }
}
