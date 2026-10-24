import XCTest

@testable import CrestMobile

@MainActor
final class MobileTransientBrowsingTests: XCTestCase {
    func testMobileTransientPageUsesTheOwningSpaceAssignmentAndIsolatedWebsiteStore() throws {
        let session = SessionState.Seed.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let pages = MobileBrowserPageStore(browser: .hostingPages(session), usesEphemeralWebsiteDataStores: true)
        let blankURL = try XCTUnwrap(URL(string: "about:blank"))

        let workLease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: blankURL,
                in: pages.browser.hostedSpace(work.id)
            )
        )
        let personalLease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: blankURL,
                in: pages.browser.hostedSpace(personal.id)
            )
        )
        let workPage = try XCTUnwrap(workLease.page)
        let personalPage = try XCTUnwrap(personalLease.page)
        defer {
            workLease.release()
            personalLease.release()
        }

        XCTAssertEqual(workPage.spaceID, work.id)
        XCTAssertEqual(workPage.profileID, work.profileID)
        XCTAssertEqual(
            workLease.assignment,
            BrowserSpaceRuntimeAssignment(space: work)
        )
        XCTAssertEqual(
            personalLease.assignment,
            BrowserSpaceRuntimeAssignment(space: personal)
        )
        let workDataStore = workPage.webView.configuration.websiteDataStore
        let personalDataStore = personalPage.webView.configuration.websiteDataStore
        XCTAssertFalse(workDataStore.isPersistent)
        XCTAssertFalse(personalDataStore.isPersistent)
        XCTAssertEqual(
            workDataStore === personalDataStore,
            false,
            "Each profile keeps a separate nonpersistent store during isolated tests."
        )
    }

    func testMobileMemoryWarningReleasesTransientPagesBeforeTheActiveTab() throws {
        let session = SessionState.Seed.preview
        let work = try XCTUnwrap(session.spaces.first)
        let browser = BrowserStore.hostingPages(session)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        pages.select()
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(url: url, in: pages.browser.hostedSpace(work.id))
        )

        XCTAssertNotNil(lease.page)
        XCTAssertEqual(pages.retainedTransientPageCount, 1)
        pages.handleMemoryPressure(.critical)

        XCTAssertNil(lease.page)
        XCTAssertTrue(lease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pages.activePage)
        XCTAssertEqual(pages.retainedTransientPageCount, 0)
    }

    func testMobileCrossSpaceMoveRebuildsTheTabWithTheDestinationProfile() throws {
        let browser = BrowserStore.hostingPages(SessionState.Seed.preview)
        let source = try XCTUnwrap(browser.spaceModels.first)
        let destination = try XCTUnwrap(browser.spaceModels.last)
        let tab = try XCTUnwrap(source.currentTabs.first)
        browser.activateSessionTab(tab.id, in: source.id)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)

        pages.select()
        let sourcePage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(sourcePage.spaceID, source.id)

        XCTAssertTrue(
            browser.moveTab(tab.id, from: source.id, into: destination.id)
        )
        pages.reconcile()
        browser.activateSessionTab(tab.id, in: destination.id)
        pages.select()

        let destinationPage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(sourcePage === destinationPage)
        XCTAssertEqual(destinationPage.spaceID, destination.id)
        XCTAssertEqual(destinationPage.profileID, destination.profileID)
        XCTAssertFalse(
            sourcePage.webView.configuration.websiteDataStore
                === destinationPage.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(destinationPage.webView.configuration.websiteDataStore.isPersistent)
    }

    func testRecentLinkActivationOriginIsBoundedMatchingAndOneShot() throws {
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/article"))
        let differentDestination = try XCTUnwrap(URL(string: "https://example.net/other"))
        let sourcePresentation = BrowserPeekSourcePresentation(
            normalizedMinX: 0.2,
            normalizedMinY: 0.3,
            normalizedWidth: 0.4,
            normalizedHeight: 0.08,
            label: "Article"
        )
        var store = MobileLinkActivationSourceStore(maximumAge: 1.25)

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 10
        )
        XCTAssertNil(
            store.consume(destinationURL: differentDestination, uptime: 10.1),
            "An unrelated navigation must not inherit the preceding tap's position."
        )

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 20
        )
        XCTAssertNil(
            store.consume(destinationURL: destination, uptime: 21.3),
            "A delayed script navigation must use the centered fallback."
        )

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 30
        )
        XCTAssertEqual(
            store.consume(destinationURL: destination, uptime: 30.2),
            sourcePresentation
        )
        XCTAssertNil(
            store.consume(destinationURL: destination, uptime: 30.3),
            "One trusted activation point may animate only one Peek."
        )
    }

    func testPrivatePeekKeepsItsEphemeralSpaceWhenPromoted() throws {
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let privateSpace = try XCTUnwrap(browser.shownSpace)
        let sourceTab = try XCTUnwrap(browser.shownTab)
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/private-peek"))
        let request = BrowserPeekRequest(
            url: destination,
            sourceTabID: sourceTab.id,
            sourceTitle: sourceTab.title,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: privateSpace),
            trigger: .modifierClick
        )

        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(url: request.url, in: privateSpace)
        )
        let peekPage = try XCTUnwrap(lease.page)
        let privateStore = peekPage.webView.configuration.websiteDataStore
        XCTAssertEqual(request.spaceID, privateSpace.id)
        XCTAssertFalse(privateStore.isPersistent)
        XCTAssertNil(privateStore.identifier)

        let keptTabID = try XCTUnwrap(
            browser.openNewTab(url: request.url, in: request.spaceID)
        )
        let currentPrivateSpace = try XCTUnwrap(browser.shownSpace)
        XCTAssertTrue(
            pages.adoptTransientPage(lease, as: keptTabID, in: currentPrivateSpace)
        )
        XCTAssertEqual(browser.spaceModels.map(\.id), [privateSpace.id])
        XCTAssertEqual(pages.activePage?.tabID, keptTabID)
        XCTAssertTrue(
            pages.activePage?.webView.configuration.websiteDataStore === privateStore
        )
    }

}
