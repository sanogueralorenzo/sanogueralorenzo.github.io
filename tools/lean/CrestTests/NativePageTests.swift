import Foundation
import XCTest

@testable import Crest

final class NativePageTests: XCTestCase {
    private func page(tab: UUID? = UUID()) -> NativePage {
        NativePage(
            id: UUID(), profileID: UUID(), workspaceID: UUID(), spaceID: UUID(), tabID: tab, windowID: UUID(),
            transient: nil)
    }
    func testLifecycleRecordingResidencyAndCrashResultsMatchActualCrestTransitions() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/page-state-crest-baseline.json")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let page = page()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, row) in rows.enumerated() {
            let kind = try XCTUnwrap(row["kind"] as? String)
            let arguments = row["arguments"] as? [String: Any] ?? [:]
            func text(_ key: String) throws -> String { try XCTUnwrap(arguments[key] as? String) }
            func flag(_ key: String) throws -> Bool { try XCTUnwrap(arguments[key] as? Bool) }
            func time() throws -> Date { start.addingTimeInterval(try XCTUnwrap(arguments["time"] as? Double)) }
            var result: Any?
            switch kind {
            case "initial": break
            case "enter": result = page.enter(try XCTUnwrap(PagePhase.named(text("phase"))))
            case "load": page.load(try text("url"))
            case "commit": page.commit(try text("url"), sameDocument: try flag("same"))
            case "show":
                page.show(
                    PageSnapshot(
                        url: try text("url"), pendingURL: nil, title: try text("title"),
                        isLoading: try flag("loading"), security: .none,
                        media: PageMediaActivity(rawValue: try XCTUnwrap(arguments["media"] as? Int))))
            case "finish": result = page.finish(try text("url"), title: try text("title"), at: try time())
            case "retitle":
                if let title = page.retitle(at: try time()) {
                    result = ["url": title.url, "title": title.title, "visit": title.visit]
                }
            case "icon": result = page.showIcon(NativePageIcon(url: try text("url"), accent: nil))
            case "crash": result = page.crash(isShown: try flag("shown"), domain: "WK", code: 7)
            case "recover": result = page.recover()
            case "fail":
                page.fail(
                    PageFailure(
                        error: .unavailable, url: "https://failed.example/", replacedDocument: false, domain: "WK",
                        code: 8))
            case "leaveFailure": page.leaveFailure()
            case "restoring": page.restoring("https://restoring.example/")
            case "cancel": page.cancelLoad()
            case "seen": result = page.seen(try flag("shown"), at: try time())
            default: return XCTFail("Unknown fixture action")
            }
            let live = page.live
            let failure: Any =
                live.failure.map { reason -> Any in
                    [
                        "url": reason.url as Any? ?? NSNull(), "replaced": reason.replacedDocument,
                        "domain": reason.domain,
                        "code": reason.code, "error": reason.error.name,
                    ]
                } ?? NSNull()
            let actual: [String: Any] = [
                "phase": page.phase.name, "documents": page.documents,
                "address": page.documentAddress as Any? ?? NSNull(),
                "awaits": page.awaitsFirstLoad, "icon": page.icon?.url as Any? ?? NSNull(),
                "pip": page.showsPictureInPicture,
                "media": page.runsMedia,
                "hidden": page.hiddenSince.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } as Any?
                    ?? NSNull(),
                "recovers": page.recoversWhenShown,
                "live": [
                    "url": live.url as Any? ?? NSNull(), "pending": live.pendingURL as Any? ?? NSNull(),
                    "title": live.title,
                    "loading": live.isLoading, "back": live.canGoBack, "forward": live.canGoForward,
                    "address": live.address as Any? ?? NSNull(), "media": live.media.rawValue, "failure": failure,
                ],
            ]
            let expected = try XCTUnwrap(row["expected"] as? [String: Any])
            let message = "Step \(index), \(kind)"
            XCTAssertTrue(
                NSDictionary(dictionary: actual).isEqual(to: expected), "\(message): \(actual) vs \(expected)")
            XCTAssertTrue(
                NSDictionary(dictionary: ["value": result ?? NSNull()]).isEqual(to: ["value": row["result"] ?? NSNull()]
                ), message)
        }
        XCTAssertGreaterThan(rows.count, 50)
    }
    func testOnlyAllowedPhasesFollowAndMovingRetainsRendererProfileAndDocumentIdentity() {
        for first in PagePhase.all {
            for next in PagePhase.all {
                let page = page()
                if first != .opening { XCTAssertTrue(page.enter(first)) }
                let expected =
                    next == .live || next == .failed ? first == .opening : next == .closed && first.holdsEnginePage
                XCTAssertEqual(page.enter(next), expected, "\(first.name) -> \(next.name)")
            }
        }
        let page = page()
        let profile = page.profileID
        page.commit("https://page.example/", sameDocument: false)
        let workspace = UUID()
        let space = UUID()
        let tab = UUID()
        let window = UUID()
        page.move(workspace: workspace, space: space, tab: tab, window: window)
        XCTAssertEqual(page.profileID, profile)
        XCTAssertEqual(page.documents, 1)
        XCTAssertEqual(page.state.workspaceID, workspace)
        XCTAssertEqual(page.state.spaceID, space)
        XCTAssertEqual(page.state.tabID, tab)
        XCTAssertEqual(page.state.windowID, window)
    }
    func testFragmentsDoNotStartNewRecordsAndTransientPagesNeverAdoptIconsForTabs() {
        let page = page(tab: nil)
        page.enter(.live)
        page.commit("https://page.example/", sameDocument: false)
        XCTAssertFalse(page.showIcon(NativePageIcon(url: "https://page.example/", accent: nil)))
        XCTAssertTrue(page.finish("https://page.example/", title: "Page", at: .now))
        page.commit("https://page.example/#anchor", sameDocument: true)
        XCTAssertFalse(page.finish("https://page.example/#anchor", title: "Anchor", at: .now))
        XCTAssertEqual(page.documents, 1)
        XCTAssertNotNil(page.icon)
        XCTAssertFalse(page.showIcon(NativePageIcon(url: "https://page.example/", accent: nil)))
        page.commit("https://page.example/new", sameDocument: false)
        XCTAssertEqual(page.documents, 2)
        XCTAssertNil(page.icon)
        XCTAssertTrue(page.finish("https://page.example/new", title: "New", at: .now))
    }
}
