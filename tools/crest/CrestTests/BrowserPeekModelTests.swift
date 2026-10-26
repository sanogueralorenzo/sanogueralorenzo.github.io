import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPeekModelTests: XCTestCase {
    func testCrossSpacePromotionRebuildsUnderTheDestinationProfile() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let sourcePage = try XCTUnwrap(context.model.pageLease?.page)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertNil(context.model.pageLease?.page)
        XCTAssertFalse(context.pages.activePage === sourcePage)
        XCTAssertEqual(
            context.pages.activePage?.profileID,
            context.destination.profileID
        )
    }

    func testRelockedSourceRejectsLatePromotionPrepareAndRestore() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.spaceModel(context.source.id))

        XCTAssertFalse(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertEqual(
            context.browser.spaceModel(context.destination.id)?.tabs.models.count,
            context.destination.tabs.count
        )

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertFalse(context.model.preparePage(isActive: true))
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertEqual(
            context.model.pageLease?.assignment,
            BrowserSpaceRuntimeAssignment(space: lockedSource)
        )
    }

    private func makeContext(
        browsingMode: BrowserBrowsingMode = .privateBrowsing, sourceURL: URL? = nil
    ) throws -> PeekTestContext {
        let source = makeSpace(name: "Source", url: sourceURL)
        let destination = makeSpace(name: "Destination")
        let sourceTabID = try XCTUnwrap(source.tabs.first?.id)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: sourceTabID],
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = BrowserPagePool(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            sourceTabID: sourceTabID,
            sourceTitle: source.settings.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source),
            trigger: .modifierClick
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        // The core refuses a locked Space's pages through the same grants.
        browser.attachSpaceAccess(spaceAccess)
        return PeekTestContext(
            source: source,
            destination: destination,
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            request: request,
            spaceAccess: spaceAccess,
            model: BrowserPeekModel(
                request: request,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                coordinator: coordinator
            )
        )
    }

    private func makeSpace(name: String, url: URL? = nil) -> SpaceState.Seed {
        let tab = url.map { TabState.Seed(title: name, url: $0, placement: .current) } ?? .startPage()
        return SpaceState.Seed(
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private struct PeekTestContext {
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let browser: BrowserStore
        let pages: BrowserPagePool
        let coordinator: BrowserTransientBrowsingCoordinator
        let request: BrowserPeekRequest
        let spaceAccess: BrowserSpaceAccessController
        let model: BrowserPeekModel
    }
}
