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

    func testLockedSpaceRedactsTitleAndURLBeforePageReconciliation() async {
        let model = makeModel()
        model.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: model.browser.selectedSpaceID)
        let space = model.browser.shownSpace!
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
        let unlocked = await model.spaceAccess.unlock(space)
        XCTAssertTrue(unlocked)
        XCTAssertEqual(model.windowTitle, "Alpha")
        let changed = expectation(description: "Window title observes relock")
        withObservationTracking {
            _ = model.windowTitle
        } onChange: {
            changed.fulfill()
        }
        model.spaceAccess.lock(space.id)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
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
            name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: tabs
        )
        let browser =
            browser
            ?? BrowserStore.hostingPages(SessionState.Seed(spaces: [space] + extra))
        let spaceAccess = BrowserSpaceAccessController(authenticator: TitleAuthenticator())
        browser.attachSpaceAccess(spaceAccess)
        return BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(browser: browser),
            chrome: BrowserChromeState(),
            spaceAccess: spaceAccess,
            windowState: nil, startupBehavior: .lastActiveTab,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
    }

    private final class TitleAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason: String) async throws -> Bool { true }
    }
}
