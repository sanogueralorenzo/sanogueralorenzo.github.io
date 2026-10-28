import XCTest

@testable import Crest

@MainActor
final class BrowserGitHubIntegrationTests: XCTestCase {
    private let result =
        #"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":[{"permalink":"https://github.com/team/browser/pull/42","title":"Session recovery","repoNameWithOwner":"team/browser","number":42,"author":{"displayLogin":"reviewer"}}]}}}"#

    func testDashboardQueriesRespectSelectedRelationshipsAndRejectForeignLinks() async throws {
        let session = GitHubSessionStub(body: result)
        var options = GitHubLiveFolderOptions.default
        options.authorMe = true
        options.reviewRequested = true
        let items = try await BrowserGitHubClient().read(from: session, options: options)
        XCTAssertEqual(items.map(\.number), [42])
        XCTAssertEqual(items.map(\.author), ["reviewer"])
        XCTAssertEqual(session.requests.count, 2)
        XCTAssertTrue(session.requests.allSatisfy { $0.host == "github.com" && $0.path == "/pulls" })
        XCTAssertTrue(
            session.requests.contains {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value?.contains(
                    "review-requested:@me") == true
            })
        session.body = result.replacingOccurrences(of: "https://github.com/team", with: "https://attacker.example/team")
        do {
            _ = try await BrowserGitHubClient().read(from: session)
            XCTFail("A dashboard cannot introduce links to another service.")
        } catch { XCTAssertEqual(error as? BrowserGitHubFailure, .invalidResponse) }
    }

    func testDraftAndRepositoryFiltersReachGitHubAndNoFiltersLeaveExistingItemsUntouched() async throws {
        let session = GitHubSessionStub(body: result)
        var options = GitHubLiveFolderOptions.default
        options.assignedMe = false
        options.authorMe = true
        options.reviewRequested = true
        options.includeDrafts = false
        options.excludedRepositories = ["team/hidden"]
        let client = BrowserGitHubClient()
        let items = try await client.read(from: session, options: options)
        let query = session.requests.last.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        }
        XCTAssertEqual(
            query,
            "is:pr is:open archived:false sort:updated-desc draft:false -repo:team/hidden (author:@me OR review-requested:@me)"
        )
        let integration = BrowserGitHubIntegration()
        await integration.refresh(fetch: { items }, isCurrent: { true })
        let count = session.requests.count
        options.authorMe = false
        options.reviewRequested = false
        await integration.refresh(
            fetch: { try await client.read(from: session, options: options) }, isCurrent: { true })
        XCTAssertEqual(session.requests.count, count)
        XCTAssertEqual(integration.items, items)
        XCTAssertEqual(integration.failure, .noFilters)
    }

    func testRetiredRefreshAndRevokedAuthorizationCannotPublish() async throws {
        let integration = BrowserGitHubIntegration()
        var continuation: CheckedContinuation<[BrowserGitHubPullRequest], any Error>?
        let items = try await BrowserGitHubClient().read(from: GitHubSessionStub(body: result))
        await integration.refresh(fetch: { items }, isCurrent: { true })
        let previousFetch = integration.lastFetched
        let pending = Task {
            await integration.refresh(
                fetch: {
                    try await withCheckedThrowingContinuation { continuation = $0 }
                }, isCurrent: { true })
        }
        while continuation == nil { await Task.yield() }
        integration.retireRefresh()
        continuation?.resume(returning: [])
        await pending.value
        XCTAssertEqual(integration.items, items)
        XCTAssertTrue(integration.hasRefreshed)
        XCTAssertEqual(integration.lastFetched, previousFetch)
        var authorized = true
        await integration.refresh(
            fetch: {
                authorized = false
                return items
            }, isCurrent: { authorized })
        XCTAssertEqual(integration.items, items)
        await integration.refresh(fetch: { items }, isCurrent: { true })
        XCTAssertEqual(integration.items, items)
    }

    func testFailedRefreshPreservesResultsAndSignOutClearsThem() async throws {
        let integration = BrowserGitHubIntegration()
        let session = GitHubSessionStub(body: result)
        let client = BrowserGitHubClient()
        await integration.refresh(fetch: { try await client.read(from: session) }, isCurrent: { true })
        let items = integration.items
        session.status = 503
        await integration.refresh(fetch: { try await client.read(from: session) }, isCurrent: { true })
        XCTAssertEqual(integration.items, items)
        XCTAssertEqual(integration.failure, .unavailable)
        session.status = 302
        await integration.refresh(fetch: { try await client.read(from: session) }, isCurrent: { true })
        XCTAssertTrue(integration.items.isEmpty)
        XCTAssertEqual(integration.failure, .notSignedIn)
    }

    func testHTMLDashboardIsParsedWithoutExecutingWebsiteCodeAndMalformedResultsAreRejected() async throws {
        let session = GitHubSessionStub(
            body: """
                <html><head><meta name='octolytics-actor-login' content='first'></head><body>
                <script>throw new Error('Must never execute');</script>
                <div id='issue_41'><a id='issue_41_link' href='/team/browser/pull/41'>HTML &amp; review</a>
                <span class='opened-by'><a>first</a></span></div></body></html>
                """)
        var options = GitHubLiveFolderOptions.default
        options.authorMe = true
        let items = try await BrowserGitHubClient().read(from: session, options: options)
        XCTAssertEqual(items.map(\.title), ["HTML & review"])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(session.requests.count, 3)
        XCTAssertTrue(
            session.requests.compactMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            }.allSatisfy { !$0.contains(" OR ") })
        session.body =
            "<html><head><meta name='octolytics-actor-login' content='first'></head><body>Unknown dashboard</body></html>"
        do {
            _ = try await BrowserGitHubClient().read(from: session)
            XCTFail("An unrecognized dashboard cannot empty a folder.")
        } catch { XCTAssertEqual(error as? BrowserGitHubFailure, .invalidResponse) }
        session.body = "<html><body>Sign in</body></html>"
        do {
            _ = try await BrowserGitHubClient().read(from: session)
            XCTFail("A signed-out document cannot supply results.")
        } catch { XCTAssertEqual(error as? BrowserGitHubFailure, .notSignedIn) }
    }

    func testSessionChangedAfterLastResponseCannotPublishCollectedItems() async {
        let session = GitHubSessionStub(body: result)
        session.expired = true
        let integration = BrowserGitHubIntegration()
        await integration.refresh(fetch: { try await BrowserGitHubClient().read(from: session) }, isCurrent: { true })
        XCTAssertTrue(integration.items.isEmpty)
        XCTAssertFalse(integration.hasRefreshed)
        XCTAssertEqual(integration.failure, .notSignedIn)
    }

    func testLiveFolderCreationReusesItsFolderAndRejectsAnInactiveSpace() throws {
        let space = SpaceState.Seed(name: "Work", folders: [], tabs: [])
        let other = SpaceState.Seed(name: "Personal", folders: [], tabs: [])
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [space, other]))
        let action = BrowserGitHubFolderAction(
            browser: browser, assignment: BrowserSpaceRuntimeAssignment(space: space))
        let folderID = try XCTUnwrap(action.create())
        XCTAssertEqual(browser.spaceModel(space.id)?.folders.model(folderID)?.source, .gitHubPullRequests)
        XCTAssertEqual(action.create(), folderID)
        XCTAssertEqual(browser.spaceModel(space.id)?.folders.models.count, 1)
        browser.selectSpace(other.id)
        let before = browser.sessionSeed
        XCTAssertNil(action.create())
        XCTAssertEqual(browser.sessionSeed, before)
    }
}

@MainActor
private final class GitHubSessionStub: BrowserIntegrationSession {
    var body: String
    var status = 200
    var expired = false
    var revision = 0
    var requests: [URL] = []
    init(body: String) { self.body = body }
    func get(_ url: URL, accept: String) async throws -> BrowserIntegrationResponse {
        requests.append(url)
        return BrowserIntegrationResponse(url: url, status: status, data: Data(body.utf8))
    }
    func validate() async throws {
        if expired { throw BrowserIntegrationSessionFailure.sessionChanged }
    }
    func invalidate() { revision += 1 }
}
