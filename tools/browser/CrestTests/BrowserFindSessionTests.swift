import XCTest

@testable import Crest

@MainActor
final class BrowserFindSessionTests: XCTestCase {
    func testSearchConfiguresNativeFindAndPublishesItsResult() throws {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.find("Crest", direction: .backward, using: executor)

        let request = try XCTUnwrap(executor.requests.first)
        XCTAssertEqual(request.query, "Crest")
        XCTAssertEqual(session.query, "Crest")
        XCTAssertTrue(request.configuration.backwards)
        XCTAssertFalse(request.configuration.caseSensitive)
        XCTAssertEqual(session.matchState, .searching)

        executor.completeRequest(at: 0, result: BrowserFindResult(matchCount: 12, activeMatch: 3))
        XCTAssertEqual(session.matchState, .found)
        XCTAssertEqual(session.matches, BrowserFindMatches(active: 3, total: 12))

        session.find("Crest!", using: executor)
        executor.completeRequest(at: 1, result: BrowserFindResult(matchCount: 0, activeMatch: 0))
        XCTAssertEqual(session.matchState, .notFound)
        XCTAssertNil(session.matches)
    }

    func testNewerSearchSupersedesAnOlderCompletion() {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.find("first", using: executor)
        session.find("second", using: executor)

        executor.completeRequest(at: 1, result: BrowserFindResult(matchFound: true))
        XCTAssertEqual(session.matchState, .found)

        executor.completeRequest(at: 0, result: .notFound)
        XCTAssertEqual(session.matchState, .found)
    }

    func testEmptySearchAndDismissClearNativeFindState() {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()

        session.present(hasLoadedPage: true)
        session.find("", using: executor)

        XCTAssertEqual(executor.requests.map(\.query), [""])
        XCTAssertEqual(session.query, "")
        XCTAssertEqual(session.matchState, .idle)
        XCTAssertTrue(session.isPresented)

        session.dismiss(using: executor)

        XCTAssertEqual(executor.requests.map(\.query), ["", ""])
        XCTAssertEqual(session.query, "")
        XCTAssertEqual(session.matchState, .idle)
        XCTAssertFalse(session.isPresented)
    }

    func testFindingAgainReusesTheLastQueryAndLeavesFocusWithThePage() throws {
        let executor = BrowserFindExecutorSpy()
        let session = BrowserFindSession()
        XCTAssertFalse(session.canFindAgain)

        session.present(hasLoadedPage: true)
        session.find("Crest", using: executor)
        session.dismiss(using: executor)
        XCTAssertTrue(session.canFindAgain)

        let focusRequest = session.focusRequest
        session.findAgain(.backward, hasLoadedPage: true, using: executor)

        let request = try XCTUnwrap(executor.requests.last)
        XCTAssertEqual(request.query, "Crest")
        XCTAssertTrue(request.configuration.backwards)
        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(session.query, "Crest")
        XCTAssertFalse(session.focusesQueryField)
        XCTAssertEqual(session.focusRequest, focusRequest)

        // Asking for find again hands the field its focus back.
        session.present(hasLoadedPage: true)
        XCTAssertTrue(session.focusesQueryField)

        // An emptied field leaves nothing to find again while the bar is open.
        session.find("", using: executor)
        XCTAssertFalse(session.canFindAgain)
    }
}

@MainActor
private final class BrowserFindExecutorSpy: BrowserFindExecuting {
    struct Request {
        let query: String
        let configuration: BrowserFindConfiguration
        let completion: @MainActor (BrowserFindResult) -> Void
    }

    private(set) var requests: [Request] = []

    func performFind(
        _ query: String,
        configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    ) {
        requests.append(
            Request(
                query: query,
                configuration: configuration,
                completion: completion
            )
        )
    }

    func completeRequest(at index: Int, result: BrowserFindResult) {
        requests[index].completion(result)
    }
}
