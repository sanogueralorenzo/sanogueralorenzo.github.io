import Observation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserQuickWindowModelTests: XCTestCase {
    func testWindowTitleFollowsOnlyItsLeaseAndRedactsOnLock() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let page = try XCTUnwrap(context.model.page)
        page.webView.loadHTMLString("<title>Quick page</title>", baseURL: context.model.presentedRequest.url)
        try await waitUntil { page.live.title == "Quick page" && !page.live.isLoading }
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Quick page")
        let selected = try XCTUnwrap(context.browser.shownTab)
        XCTAssertTrue(
            context.browser.setTabCustomTitle("Unrelated selected tab", for: selected.id, in: context.source.id))
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Quick page")
        let changed = expectation(description: "Quick Window observes document title")
        withObservationTracking {
            _ = context.model.windowTitle(for: context.requestBinding.request)
        } onChange: {
            changed.fulfill()
        }
        try await page.webView.evaluateJavaScript("document.title = 'Updated quick page'")
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(context.model.windowTitle(for: context.requestBinding.request), "Updated quick page")
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        XCTAssertEqual(
            context.model.windowTitle(for: context.requestBinding.request), String(localized: "Quick Window"))
    }

    func testRelockedSourceRejectsLatePromotionAndRestore() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)

        XCTAssertFalse(context.model.promote(to: BrowserSpaceRuntimeAssignment(space: context.destination)))
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )

        let rejectedURL = try XCTUnwrap(
            URL(string: "https://locked-source.crest.test/rejected")
        )
        let presentedRequest = context.model.presentedRequest
        context.model.open(rejectedURL, isActive: true)
        XCTAssertEqual(context.model.presentedRequest, presentedRequest)
        XCTAssertTrue(context.model.pageLease === lease)

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        context.model.preparePage(isActive: true)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
    }

    private func makeContext(
        startsEmpty: Bool = false,
        supportsLivePagePromotion: Bool = false,
        browsingMode: BrowserBrowsingMode = .privateBrowsing
    ) throws -> QuickWindowTestContext {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = BrowserPagePool(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: source)
        let request =
            startsEmpty
            ? BrowserQuickWindowRequest.empty(spaceAssignment: assignment)
            : BrowserQuickWindowRequest(
                url: try XCTUnwrap(URL(string: "about:blank")),
                spaceAssignment: assignment
            )
        let requestBinding = QuickWindowRequestBinding(request: request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        // The core refuses a locked Space's pages through the same grants.
        browser.attachSpaceAccess(spaceAccess)
        let model = BrowserQuickWindowModel(
            request: request,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            supportsLivePagePromotion: supportsLivePagePromotion,
            preferences: .isolated,
            requestLifecycle: requestBinding.lifecycle
        )
        return QuickWindowTestContext(
            source: source,
            destination: destination,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            requestBinding: requestBinding,
            model: model
        )
    }

    private func makeSpace(name: String) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage()
        return SpaceState.Seed(
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for Quick Window state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct QuickWindowTestContext {
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let browser: BrowserStore
        let pages: BrowserPagePool
        let spaceAccess: BrowserSpaceAccessController
        let requestBinding: QuickWindowRequestBinding
        let model: BrowserQuickWindowModel
    }

    @MainActor
    private final class QuickWindowRequestBinding {
        var request: BrowserQuickWindowRequest
        var rejectActionReads = false

        init(request: BrowserQuickWindowRequest) {
            self.request = request
        }

        var lifecycle: BrowserQuickWindowRequestLifecycle {
            BrowserQuickWindowRequestLifecycle(
                isCurrent: { [weak self] expected in
                    self?.rejectActionReads == false
                        && self?.request.hasSamePresentationIdentity(as: expected) == true
                },
                replace: { [weak self] expected, revised in
                    guard
                        self?.request.hasSamePresentationIdentity(as: expected)
                            == true
                    else { return false }
                    self?.request = revised
                    return true
                }
            )
        }
    }
}
