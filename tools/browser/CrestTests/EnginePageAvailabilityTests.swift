import Foundation
import XCTest

@testable import Crest

@MainActor
final class EnginePageAvailabilityTests: XCTestCase {
    func testOnlyInitialViewSetupIsAcceptedWhileTheNativeEngineStarts() {
        var starts = 0
        let pages = NativeEnginePages(start: { starts += 1 }, present: { _ in })
        let pageID = UUID()
        XCTAssertFalse(pages.request(ReloadPage(pageID: pageID, bypassesCache: false)))
        XCTAssertEqual(starts, 0, "A refused user action must not start the engine or be replayed later.")
        XCTAssertTrue(pages.request(WatchPage(pageID: pageID)))
        XCTAssertTrue(pages.request(ZoomPage(pageID: pageID, factor: 1.5)))
        // A tab a launch shows restores its history before the engine starts.
        let restore = RestoreInteractionState(pageID: pageID, state: Data([1]), expectedURL: "https://example.com/")
        XCTAssertTrue(pages.request(restore))
        XCTAssertEqual(starts, 3)
        XCTAssertFalse(pages.isReady)
    }

    func testDeferredAndClosedPagesHaveNoQueryableDocument() {
        let pages = StartingEnginePages()
        let page = EnginePage(
            id: UUID(), pages: pages, historyFamily: .chromium, historyVersion: { "1" }, inspectorPanels: [])

        XCTAssertTrue(page.mediaActivity.isEmpty)
        XCTAssertNil(page.serverTrust(host: "example.com"))
        XCTAssertFalse(page.isInspected)
        XCTAssertNil(page.savedHistory())
        XCTAssertEqual(pages.queries, 0)

        pages.isReady = true
        XCTAssertEqual(page.mediaActivity, [.playing])
        XCTAssertEqual(pages.queries, 1)

        page.close()
        XCTAssertTrue(page.mediaActivity.isEmpty)
        XCTAssertNil(page.serverTrust(host: "example.com"))
        XCTAssertFalse(page.isInspected)
        XCTAssertEqual(pages.queries, 1)
    }

    func testRequestedZoomSurvivesDocumentCommitsAndViewRecreation() {
        let pages = ResettingZoomEnginePages()
        let page = EnginePage(
            id: UUID(), pages: pages, historyFamily: .chromium, historyVersion: { nil }, inspectorPanels: [])

        page.receive(.pageViewReady(PageViewReady(pageID: page.id)))
        XCTAssertEqual(pages.requests, 0, "A page with no zoom request must leave the engine's value alone.")
        pages.acceptsZoom = false
        page.zoom(to: 1.5)
        XCTAssertEqual(pages.renderedZoom, 1)
        pages.acceptsZoom = true
        page.receive(.pageViewReady(PageViewReady(pageID: page.id)))
        XCTAssertEqual(pages.renderedZoom, 1.5)
        pages.commit(page)
        XCTAssertEqual(pages.renderedZoom, 1.5, "The first document must render at the configured default.")

        page.zoom(to: CGFloat(1.5).pageZoomIncreased)
        XCTAssertEqual(pages.renderedZoom, 1.75)
        pages.commit(page)
        XCTAssertEqual(pages.renderedZoom, 1.75, "Navigation must retain a manual page override.")

        page.zoom(to: 1.23456)
        pages.commit(page)
        XCTAssertEqual(pages.renderedZoom, 1.23456, "A changed default must retain its continuous multiplier.")

        pages.renderedZoom = 1
        page.receive(.pageViewReady(PageViewReady(pageID: page.id)))
        XCTAssertEqual(pages.renderedZoom, 1.23456)

        pages.renderedZoom = 1
        page.receive(.pageNavigationFailed(PageNavigationFailed(pageID: page.id)))
        XCTAssertEqual(pages.renderedZoom, 1.23456, "An engine error document must retain the requested zoom.")

        page.close()
        let requestsBeforeClosing = pages.requests
        page.zoom(to: 2)
        pages.commit(page)
        XCTAssertEqual(pages.renderedZoom, 1, "A closed page must not send further zoom requests.")
        XCTAssertEqual(pages.requests, requestsBeforeClosing)
    }
}

@MainActor
private final class ResettingZoomEnginePages: EnginePages {
    // MARK: - Variables

    var renderedZoom: Double = 1
    var acceptsZoom = true
    private(set) var requests = 0

    // MARK: - Actions - Requests

    func attach(_ page: EnginePage) {}

    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        guard let zoom = request as? ZoomPage else {
            preconditionFailure("This engine only accepts zoom requests.")
        }
        requests += 1
        if acceptsZoom { renderedZoom = zoom.factor }
        var reader = WireReader([acceptsZoom ? 1 : 0])
        do { return try Request.decodeAnswer(from: &reader) } catch {
            preconditionFailure("Zoom must use its generated Boolean answer codec.")
        }
    }

    func commit(_ page: EnginePage) {
        // Chromium clears isolated zoom on every committed new document.
        renderedZoom = 1
        page.receive(
            .pageNavigationCommitted(
                PageNavigationCommitted(pageID: page.id, url: "https://example.com", isLoading: false)))
    }
}

@MainActor
private final class StartingEnginePages: EnginePages {
    var isReady = false
    private(set) var queries = 0

    func attach(_ page: EnginePage) {}

    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        queries += 1
        precondition(request is PageMedia)
        var writer = WireWriter()
        PageMediaState(activity: [.playing]).encode(into: &writer)
        var reader = WireReader(writer.bytes)
        do { return try Request.decodeAnswer(from: &reader) } catch {
            preconditionFailure("The media answer must use its generated codec.")
        }
    }
}
