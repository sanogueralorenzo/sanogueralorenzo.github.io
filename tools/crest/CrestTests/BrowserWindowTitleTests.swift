import AppKit
import Observation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWindowTitleTests: XCTestCase {

    func testBlankTitlesUseSafeHostWithoutCredentialsPathOrQuery() {
        let model = makeModel { tabs in
            tabs[0].title = " \n\t "
            tabs[0].url = "https://user:secret@www.example.com:8443/private?token=secret"
        }
        XCTAssertEqual(model.windowTitle, "example.com:8443")
        let local = makeModel { tabs in
            tabs[0].title = " \n\t "
            tabs[0].url = "file:///private/secret.html"
        }
        XCTAssertEqual(local.windowTitle, ProductIdentity.name)
    }

    func testWindowLocalSelectionDoesNotFollowAnotherWindow() {
        let first = makeModel()
        let second = makeModel(browser: first.browser.makeWindowStore())
        second.browser.selectTab(second.browser.shownSpace!.tabs.models[1].id)
        second.browser.seedSelectedTabNavigation(to: nil, titled: "Other window changed")
        XCTAssertEqual(first.windowTitle, "Alpha")
        XCTAssertEqual(second.windowTitle, "Other window changed")
    }

    func testBackgroundMetadataDoesNotOverwriteFocusedSplitMember() {
        let group = UUID()
        let model = makeModel { tabs in
            tabs[0].splitGroupID = group
            tabs[1].splitGroupID = group
            // The unfocused member's page recorded a new title.
            tabs[1].title = "Background Beta"
        }
        let space = model.browser.shownSpace!
        XCTAssertEqual(model.windowTitle, "Alpha")
        model.browser.selectTab(space.tabs.models[1].id)
        XCTAssertEqual(model.windowTitle, "Background Beta")
        model.browser.selectTab(space.tabs.models[0].id)
        XCTAssertEqual(model.windowTitle, "Alpha")
    }

    func testDeletingSpaceImmediatelyRedactsItsTitle() {
        let model = makeModel()
        XCTAssertTrue(model.browser.family.beginDeletingSpace(model.browser.selectedSpaceID))
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testSpaceSwitchRejectsThePreviousActivePage() async throws {
        let beta = TabState.Seed(title: "Beta", url: URL(string: "https://beta.crest.test"), placement: .current)
        let destination = SpaceState.Seed(
            name: "Other",
            folders: [], tabs: [beta]
        )
        let model = makeModel(adding: [destination])
        model.pages.select()
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Live Alpha", into: page)
        model.browser.selectSpace(destination.id)
        XCTAssertEqual(model.pages.activeTabID, model.browser.spaceModels[0].tabs.models[0].id)
        XCTAssertEqual(model.windowTitle, "Beta")
        let sessionBeforePageCallbacks = model.browser.sessionSeed
        model.address = "Destination address draft"

        model.synchronizePageMetadata()

        XCTAssertEqual(model.browser.sessionSeed, sessionBeforePageCallbacks)
        XCTAssertEqual(model.address, "Destination address draft")
    }

    /// A window over a Space showing Alpha, then Beta, with `adding` after it
    /// and its tabs as `configure` leaves them; or over `browser`'s session.
    private func makeModel(
        browser: BrowserStore? = nil, adding extra: [SpaceState.Seed] = [],
        configure: (inout [TabState.Seed]) -> Void = { _ in }
    ) -> BrowserRootModel {
        let alpha = TabState.Seed(title: "Alpha", url: URL(string: "https://alpha.crest.test"), placement: .current)
        let beta = TabState.Seed(title: "Beta", url: URL(string: "https://beta.crest.test"), placement: .current)
        var tabs = [alpha, beta]
        configure(&tabs)
        let space = SpaceState.Seed(
            name: "Test",
            folders: [], tabs: tabs
        )
        let browser =
            browser
            ?? BrowserStore.hostingPages(SessionState.Seed(spaces: [space] + extra))
        return BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(browser: browser),
            chrome: BrowserChromeState(),
            windowState: nil,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
    }

    private func load(_ title: String, into page: BrowserPage) async throws {
        page.webView.loadSimulatedRequest(
            URLRequest(url: URL(string: "https://alpha.crest.test")!),
            responseHTML: "<html><head><title>\(title)</title></head><body>Fixture</body></html>"
        )
        try await waitUntil { page.live.title == title && !page.live.isLoading }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for document metadata")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

}
